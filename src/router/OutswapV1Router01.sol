//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IOutswapV1Router.sol";
import "./interfaces/IORETH.sol";
import "./interfaces/IORUSD.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/OutswapV1Library01.sol";
import "../core/interfaces/IOutswapV1ERC20.sol";
import "../core/interfaces/IOutswapV1Factory.sol";
import "../blast/GasManagerable.sol";
import "../referral/interfaces/IReferralManager.sol";

contract OutswapV1Router01 is IOutswapV1Router, GasManagerable {
    address public immutable override factory;
    address public immutable ORETH;
    address public immutable ORUSD;
    address public immutable USDB;
    address public immutable referralManager;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, Expired());
        _;
    }

    constructor(
        address _factory, 
        address _orETH, 
        address _orUSD, 
        address _usdb, 
        address _referralManager,
        address _gasManager
    ) GasManagerable(_gasManager) {
        factory = _factory;
        ORETH = _orETH;
        ORUSD = _orUSD;
        USDB = _usdb;
        referralManager = _referralManager;
        IERC20(_usdb).approve(_orUSD, type(uint256).max);
    }

    receive() external payable {
        // only accept ETH via fallback from the ORETH contract
        require(msg.sender == ORETH, InvaildETHSender());
    }

    /**
     * ADD LIQUIDITY *
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IOutswapV1Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IOutswapV1Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = OutswapV1Library01.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = OutswapV1Library01.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, InsufficientBAmount());
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = OutswapV1Library01.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, InsufficientAAmount());
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = OutswapV1Library01.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IOutswapV1Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) = _addLiquidity(token, ORETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = OutswapV1Library01.pairFor(factory, token, ORETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IORETH(ORETH).deposit{value: amountETH}();
        assert(IORETH(ORETH).transfer(pair, amountETH));
        liquidity = IOutswapV1Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    function addLiquidityUSDB(
        address token,
        uint256 amountTokenDesired,
        uint256 amountUSDBDesired,
        uint256 amountTokenMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountUSDB, uint256 liquidity) {
        (amountToken, amountUSDB) = _addLiquidity(token, ORUSD, amountTokenDesired, amountUSDBDesired, amountTokenMin, amountUSDBMin);
        address pair = OutswapV1Library01.pairFor(factory, token, ORUSD);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        TransferHelper.safeTransferFrom(USDB, msg.sender, address(this), amountUSDB);
        IORUSD(ORUSD).deposit(amountUSDB);
        assert(IORUSD(ORUSD).transfer(pair, amountUSDB));
        liquidity = IOutswapV1Pair(pair).mint(to);
    }

    function addLiquidityETHAndUSDB(
        uint256 amountUSDBDesired,
        uint256 amountETHMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256 amountETH, uint256 amountUSDB, uint256 liquidity) {
        (amountETH, amountUSDB) = _addLiquidity(ORETH, ORUSD, msg.value, amountUSDBDesired, amountETHMin, amountUSDBMin);
        address pair = OutswapV1Library01.pairFor(factory, ORETH, ORUSD);
        IORETH(ORETH).deposit{value: amountETH}();
        assert(IORETH(ORETH).transfer(pair, amountETH));
        TransferHelper.safeTransferFrom(USDB, msg.sender, address(this), amountUSDB);
        IORUSD(ORUSD).deposit(amountUSDB);
        assert(IORUSD(ORUSD).transfer(pair, amountUSDB));
        liquidity = IOutswapV1Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = OutswapV1Library01.pairFor(factory, tokenA, tokenB);
        IOutswapV1Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IOutswapV1Pair(pair).burn(to);
        (address token0,) = OutswapV1Library01.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, InsufficientAAmount());
        require(amountB >= amountBMin, InsufficientBAmount());
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(token, ORETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IORETH(ORETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityUSDB(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountUSDB) {
        (amountToken, amountUSDB) = removeLiquidity(token, ORUSD, liquidity, amountTokenMin, amountUSDBMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IORUSD(ORUSD).withdraw(amountUSDB);
        TransferHelper.safeTransfer(USDB, to, amountUSDB);
    }

    function removeLiquidityETHAndUSDB(
        uint256 liquidity,
        uint256 amountETHMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH, uint256 amountUSDB) {
        (amountETH, amountUSDB) = removeLiquidity(ORETH, ORUSD, liquidity, amountETHMin, amountUSDBMin, address(this), deadline);
        IORETH(ORETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
        IORUSD(ORUSD).withdraw(amountUSDB);
        TransferHelper.safeTransfer(USDB, to, amountUSDB);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = OutswapV1Library01.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IOutswapV1ERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
        address pair = OutswapV1Library01.pairFor(factory, token, ORETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IOutswapV1ERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    function removeLiquidityUSDBWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountUSDB) {
        address pair = OutswapV1Library01.pairFor(factory, token, ORUSD);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IOutswapV1ERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountUSDB) = removeLiquidityUSDB(token, liquidity, amountTokenMin, amountUSDBMin, to, deadline);
    }

    function removeLiquidityETHAndUSDBWithPermit(
        uint256 liquidity,
        uint256 amountETHMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountETH, uint256 amountUSDB) {
        address pair = OutswapV1Library01.pairFor(factory, ORETH, ORUSD);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IOutswapV1ERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountETH, amountUSDB) = removeLiquidityETHAndUSDB(liquidity, amountETHMin, amountUSDBMin, to, deadline);
    }

    /**
     * REMOVE LIQUIDITY (supporting fee-on-transfer tokens) *
     */
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(token, ORETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IORETH(ORETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        address pair = OutswapV1Library01.pairFor(factory, token, ORETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IOutswapV1ERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    function removeLiquidityUSDBSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountUSDB) {
        (, amountUSDB) = removeLiquidity(token, ORUSD, liquidity, amountTokenMin, amountUSDBMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IORUSD(ORUSD).withdraw(amountUSDB);
        TransferHelper.safeTransfer(USDB, to, amountUSDB);
    }

    function removeLiquidityUSDBWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountUSDBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountUSDB) {
        address pair = OutswapV1Library01.pairFor(factory, token, ORUSD);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IOutswapV1ERC20(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountUSDB = removeLiquidityUSDBSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountUSDBMin, to, deadline
        );
    }

    /**
     * SWAP *
     */
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        address referrer = IReferralManager(referralManager).referrerOf(_to);
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = OutswapV1Library01.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? OutswapV1Library01.pairFor(factory, output, path[i + 2]) : _to;
            IOutswapV1Pair(OutswapV1Library01.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, referrer, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = OutswapV1Library01.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, ExcessiveInputAmount());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORETH, InvalidPath());
        amounts = OutswapV1Library01.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        IORETH(ORETH).deposit{value: amounts[0]}();
        assert(IORETH(ORETH).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == ORETH, InvalidPath());
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, ExcessiveInputAmount());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IORETH(ORETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == ORETH, InvalidPath());
        amounts = OutswapV1Library01.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IORETH(ORETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORETH, InvalidPath());
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, ExcessiveInputAmount());
        IORETH(ORETH).deposit{value: amounts[0]}();
        assert(IORETH(ORETH).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    function swapExactUSDBForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORUSD, InvalidPath());
        amounts = OutswapV1Library01.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        TransferHelper.safeTransferFrom(USDB, msg.sender, address(this), amounts[0]);
        IORUSD(ORUSD).deposit(amounts[0]);
        assert(IORUSD(ORUSD).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactUSDB(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == ORUSD, InvalidPath());
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, ExcessiveInputAmount());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IORUSD(ORUSD).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransfer(USDB, to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForUSDB(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == ORUSD, InvalidPath());
        amounts = OutswapV1Library01.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IORUSD(ORUSD).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransfer(USDB, to, amounts[amounts.length - 1]);
    }

    function swapUSDBForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORUSD, InvalidPath());
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, ExcessiveInputAmount());
        TransferHelper.safeTransferFrom(USDB, msg.sender, address(this), amounts[0]);
        IORUSD(ORUSD).deposit(amounts[0]);
        assert(IORUSD(ORUSD).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /**
     * SWAP with Pair(ETH, USDB) *
     */
    function swapExactETHForUSDB(
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORETH && path[path.length - 1] == ORUSD, InvalidPath());
        amounts = OutswapV1Library01.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        IORETH(ORETH).deposit{value: amounts[0]}();
        assert(IORETH(ORETH).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, address(this));
        IORUSD(ORUSD).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransfer(USDB, to, amounts[amounts.length - 1]);
    }

    function swapUSDBForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORUSD && path[path.length - 1] == ORETH, InvalidPath());
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, ExcessiveInputAmount());
        TransferHelper.safeTransferFrom(USDB, msg.sender, address(this), amounts[0]);
        IORUSD(ORUSD).deposit(amounts[0]);
        TransferHelper.safeTransfer(path[0], OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IORETH(ORETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactUSDBForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORUSD && path[path.length - 1] == ORETH, InvalidPath());
        amounts = OutswapV1Library01.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, InsufficientOutputAmount());
        TransferHelper.safeTransferFrom(USDB, msg.sender, address(this), amounts[0]);
        IORUSD(ORUSD).deposit(amounts[0]);
        TransferHelper.safeTransfer(path[0], OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IORETH(ORETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactUSDB(
        uint256 amountOut, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == ORETH && path[path.length - 1] == ORUSD, InvalidPath());
        amounts = OutswapV1Library01.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, ExcessiveInputAmount());
        IORETH(ORETH).deposit{value: amounts[0]}();
        assert(IORETH(ORETH).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, address(this));
        IORUSD(ORUSD).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransfer(USDB, to, amounts[amounts.length - 1]);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    /**
     * SWAP (supporting fee-on-transfer tokens) *
     */
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        address referrer = IReferralManager(referralManager).referrerOf(_to);
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = OutswapV1Library01.sortTokens(input, output);
            IOutswapV1Pair pair = IOutswapV1Pair(OutswapV1Library01.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = OutswapV1Library01.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? OutswapV1Library01.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, referrer, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amountIn
        );
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            InsufficientOutputAmount()
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == ORETH, InvalidPath());
        uint256 amountIn = msg.value;
        IORETH(ORETH).deposit{value: amountIn}();
        assert(IORETH(ORETH).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            InsufficientOutputAmount()
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == ORETH, InvalidPath());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(ORETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, InsufficientOutputAmount());
        IORETH(ORETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function swapExactUSDBForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[0] == ORUSD, InvalidPath());
        IORUSD(ORUSD).deposit(amountIn);
        assert(IORUSD(ORUSD).transfer(OutswapV1Library01.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            InsufficientOutputAmount()
        );
    }

    function swapExactTokensForUSDBSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == ORUSD, InvalidPath());
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, OutswapV1Library01.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(ORUSD).balanceOf(address(this));
        require(amountOut >= amountOutMin, InsufficientOutputAmount());
        IORUSD(ORUSD).withdraw(amountOut);
        TransferHelper.safeTransfer(USDB, to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA, 
        uint256 reserveA, 
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return OutswapV1Library01.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return OutswapV1Library01.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return OutswapV1Library01.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint256 amountIn, 
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return OutswapV1Library01.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint256 amountOut, 
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return OutswapV1Library01.getAmountsIn(factory, amountOut, path);
    }
}
