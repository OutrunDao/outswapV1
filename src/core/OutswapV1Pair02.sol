//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./OutswapV1ERC20.sol";
import "./interfaces/IOutswapV1Pair.sol";
import "./interfaces/IOutswapV1Factory.sol";
import "./interfaces/IOutswapV1Callee.sol";
import "../libraries/UQ112x112.sol";
import "../libraries/FixedPoint128.sol";
import "../blast/GasManagerable.sol";

/**
 * @title OutswapV1Pair02 - Pair fee 1%
 */
contract OutswapV1Pair02 is IOutswapV1Pair, OutswapV1ERC20, GasManagerable {
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 public feeGrowthX128; // accumulate maker fee per LP X128
    mapping(address account => uint256) public feeGrowthRecordX128; // record the feeGrowthX128 when calc maker's append fee
    mapping(address account => uint256) public unClaimedFeesX128;

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, Locked());

        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _gasManager) GasManagerable(_gasManager) {
        factory = msg.sender;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @dev View unclaimed maker fee
     */
    function viewUnClaimedFee() external view override returns (uint256 amount0, uint256 amount1) {
        address msgSender = msg.sender;
        uint256 feeAppendX128 = balanceOf(msgSender) * (feeGrowthX128 - feeGrowthRecordX128[msgSender]);
        uint256 unClaimedFeeX128 = unClaimedFeesX128[msgSender];
        if (feeAppendX128 > 0) {
            unClaimedFeeX128 += unClaimedFeeX128 + feeAppendX128;
        }

        uint256 _totalSupply = totalSupply;
        amount0 = (unClaimedFeeX128 * reserve0 / _totalSupply) / FixedPoint128.Q128;
        amount1 = (unClaimedFeeX128 * reserve1 / _totalSupply) / FixedPoint128.Q128;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, Forbidden());

        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @dev Mint liquidity (LP)
     * @param to - addree to receive LP token and calc this address's maker fee
     * @notice this low-level function should be called from a contract which performs important safety checks
     */
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _calcFeeX128(to);
        uint256 _totalSupply = totalSupply; // must be defined here since totalSupply can update in _calcFeeX128
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }

        require(liquidity > 0, InsufficientLiquidityMinted());

        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);

        kLast = uint256(reserve0) * uint256(reserve1); // reserve0 and reserve1 are up-to-date

        emit Mint(msg.sender, to, amount0, amount1);
    }

    /**
     * @dev Burn liquidity (LP) and withdraw token0 and token1
     * @param to - addree to receive token and calc this address's maker fee
     * @notice - this low-level function should be called from a contract which performs important safety checks
     */
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        _calcFeeX128(to);
        uint256 _totalSupply = totalSupply; // must be defined here since totalSupply can update in _calcFeeX128
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution

        require(amount0 > 0 && amount1 > 0, InsufficientLiquidityBurned());

        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        kLast = uint256(reserve0) * uint256(reserve1); // reserve0 and reserve1 are up-to-date

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @dev Swap token
     * @param amount0Out - Amount of token0 output
     * @param amount1Out - Amount of token0 output
     * @param to - Address to output
     * @param referrer - Address of rebate referrer
     * @notice - this low-level function should be called from a contract which performs important safety checks
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, address referrer, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, InsufficientOutputAmount());
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, InsufficientLiquidity());

        uint256 balance0;
        uint256 balance1;
        address _token0 = token0;
        address _token1 = token1;
        {
            require(to != _token0 && to != _token1, InvalidTo());

            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            if (data.length > 0) IOutswapV1Callee(to).OutswapV1Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint256 amount0In;
        uint256 amount1In;
        unchecked {
            amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
            amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        }
        require(amount0In > 0 || amount1In > 0, InsufficientInputAmount());

        uint256 rebateFee0;
        uint256 rebateFee1;
        uint256 protocolFee0;
        uint256 protocolFee1;
        {
            // 0.3% swap fee
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 10;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 10;
            
            require(
                balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * 1000 ** 2,
                ProductKLoss()
            );

            address feeTo = _feeTo();
            if (referrer == address(0)) {
                // 1% * 30% as protocolFee
                if (amount0In > 0) {
                    protocolFee0 = amount0In * 3 / 1000;
                    unchecked {
                        balance0 -= protocolFee0;
                    }
                    _safeTransfer(_token0, feeTo, protocolFee0);
                }
                
                if (amount1In > 0) {
                    protocolFee1 = amount1In * 3 / 1000;
                    unchecked {
                        balance1 -= protocolFee1;
                    }
                    _safeTransfer(_token1, feeTo, protocolFee1);
                }
            } else {
                // 1% * 30% * 20% as rebateFee, 1% * 30% * 80% as protocolFee
                if (amount0In > 0) {
                    rebateFee0 = amount0In * 3 / 5000;
                    protocolFee0 = amount0In * 3 / 1250;
                    unchecked {
                        balance0 -= rebateFee0 + protocolFee0; 
                    }
                    _safeTransfer(_token0, referrer, rebateFee0);
                    _safeTransfer(_token0, feeTo, protocolFee0);
                }
                
                if (amount1In > 0) {
                    rebateFee1 = amount1In * 3 / 5000;
                    protocolFee1 = amount1In * 3 / 1250;
                    unchecked {
                        balance1 -= rebateFee1 + protocolFee1;     
                    }
                    _safeTransfer(_token1, referrer, rebateFee1);
                    _safeTransfer(_token1, feeTo, protocolFee1);
                }
            }
        }

        _update(balance0, balance1, _reserve0, _reserve1);

        {
            uint256 k = uint256(reserve0) * uint256(reserve1);
            feeGrowthX128 += ((Math.sqrt(k) - Math.sqrt(kLast)) * FixedPoint128.Q128 / totalSupply);
            kLast = k;
        }

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit ProtocolFee(referrer, rebateFee0, rebateFee1, protocolFee0, protocolFee1);
    }

    /**
     * @dev Claim all the maker fee of msgSender
     * @notice - Claim global protocol fee simultaneously
     */
    function claimMakerFee() external override returns (uint256 amount0, uint256 amount1) {
        address msgSender = msg.sender;
        _calcFeeX128(msgSender);

        uint256 feeX128 = unClaimedFeesX128[msgSender];
        require(feeX128 > 0, InsufficientUnclaimedFee());

        uint256 unClaimedFee;
        unchecked {
            unClaimedFee = feeX128 / FixedPoint128.Q128;
        }
        unClaimedFeesX128[msgSender] = 0;
        _mint(address(this), unClaimedFee);

        // burn the fee of LP
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 _totalSupply = totalSupply;
        unchecked {
            amount0 = unClaimedFee * _reserve0 / _totalSupply;
            amount1 = unClaimedFee * _reserve1 / _totalSupply;           
        }
        require(amount0 > 0 && amount1 > 0, InsufficientLiquidityBurned());

        _burn(address(this), unClaimedFee);
        _safeTransfer(_token0, msgSender, amount0);
        _safeTransfer(_token1, msgSender, amount1);

        _update(
            IERC20(_token0).balanceOf(address(this)), IERC20(_token1).balanceOf(address(this)), _reserve0, _reserve1
        );

        kLast = uint256(reserve0) * uint256(reserve1);
    }

    /**
     * @dev Force balances to match reserves
     * @param to - Address to receive excess tokens
     */
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    /**
     * @dev Force reserves to match balances
     */
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        address owner = _msgSender();
        _calcFeeX128(owner);
        _transfer(owner, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _calcFeeX128(from);
        _transfer(from, to, value);
        return true;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), TransferFailed());
    }

    /**
     * @dev update reserves and, on the first call per block, price accumulators
     */
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, Overflow());

        uint32 blockTimestamp;
        uint32 timeElapsed;
        unchecked {
            blockTimestamp = uint32(block.timestamp % 2 ** 32);
            timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        }
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            unchecked {
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /**
     * @dev Calculate the maker fee
     */
    function _calcFeeX128(address to) private {
        uint256 _feeGrowthX128 = feeGrowthX128;
        unchecked {
            uint256 feeAppendX128 = balanceOf(to) * (_feeGrowthX128 - feeGrowthRecordX128[to]);
            if (feeAppendX128 > 0) {
                unClaimedFeesX128[to] += feeAppendX128;
            }
        }
        feeGrowthRecordX128[to] = _feeGrowthX128;
    }

    function _feeTo() internal view returns (address) {
        return IOutswapV1Factory(factory).feeTo();
    }
}
