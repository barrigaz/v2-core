// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ104x104.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ104x104 for uint208;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    uint private constant FEE_SWAP_PRECISION = 10**5;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    // pair swap fee as parts per FEE_SWAP_PRECISION
    uint public immutable feeSwap;

    struct Slot0 {
        uint104 reserve0;
        uint104 reserve1;
        uint32 blockTimestampLast;
        // pair protocol fee as a percentage of the swap fee in form simple fracton:
        // negative - fees turned off, 0 - 1, 1 - 1/2, 2 - 1/3, 3 - 1/4 etc
        int8 feeProtocol;
        // reenterance lock
        uint8 unlocked;
    }
    Slot0 private slot0; // uses single storage slot

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event


    modifier lock() {
        require(slot0.unlocked == 1, 'UniswapV2: LOCKED');
        slot0.unlocked = 0;
        _;
        slot0.unlocked = 1;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN');
        _;
    }

    function getReserves() public view returns (Reserves memory _reserves) {
        _reserves.reserve0 = slot0.reserve0;
        _reserves.reserve1 = slot0.reserve1;
        _reserves.blockTimestampLast = slot0.blockTimestampLast;
    }

    function feeProtocol() external view returns (int8) {
        return slot0.feeProtocol;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint104 reserve0, uint104 reserve1);
    event SetFeeProtocol(int8 feeProtocol);

    constructor(address _token0, address _token1, uint _feeSwap) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        feeSwap = _feeSwap;
        slot0.unlocked = 1;
    }

    // called once by the factory at time of deployment
    function initialize(int8 _feeProtocol) external onlyFactory {
        slot0.feeProtocol = _feeProtocol;
        emit SetFeeProtocol(_feeProtocol);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, Reserves memory _reserves) private {
        require(balance0 <= type(uint104).max && balance1 <= type(uint104).max, 'UniswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - _reserves.blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserves.reserve0 != 0 && _reserves.reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += UQ104x104.encode(_reserves.reserve1).uqdiv(_reserves.reserve0) * timeElapsed;
            price1CumulativeLast += UQ104x104.encode(_reserves.reserve0).uqdiv(_reserves.reserve1) * timeElapsed;
        }
        _reserves.reserve0 = slot0.reserve0 = uint104(balance0);
        _reserves.reserve1 = slot0.reserve1 = uint104(balance1);
        slot0.blockTimestampLast = blockTimestamp;
        emit Sync(_reserves.reserve0, _reserves.reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/(feeProtocol+1)th of the growth in sqrt(k)
    function _mintFee(uint104 _reserve0, uint104 _reserve1, uint _kLast, int8 _feeProtocol) private {
        uint rootK = Math.sqrt(_reserve0 * _reserve1);
        uint rootKLast = Math.sqrt(_kLast);
        if (rootK > rootKLast) {
            uint numerator = totalSupply * (rootK - rootKLast);
            uint denominator = rootK * uint8(_feeProtocol) + rootKLast;
            uint liquidity = numerator / denominator;
            if (liquidity > 0) {
                _mint(IUniswapV2Factory(factory).feeTo(), liquidity);
            }
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        Reserves memory _reserves = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserves.reserve0;
        uint amount1 = balance1 - _reserves.reserve1;

        uint _kLast = kLast; // gas savings
        int8 _feeProtocol = slot0.feeProtocol; // gas savings
        if (_kLast != 0) {
            if (_feeProtocol >= 0) _mintFee(_reserves.reserve0, _reserves.reserve1, _kLast, _feeProtocol);
            else kLast = 0;
        }
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1 - MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reserves.reserve0, amount1 * _totalSupply / _reserves.reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserves);
        // Test to make sure _reserves is passed by reference and modified by _update()
        if (_feeProtocol >= 0) kLast = _reserves.reserve0 * _reserves.reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        Reserves memory _reserves = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        uint _kLast = kLast; // gas savings
        int8 _feeProtocol = slot0.feeProtocol; // gas savings
        if (_kLast != 0) {
            if (_feeProtocol >= 0) _mintFee(_reserves.reserve0, _reserves.reserve1, _kLast, _feeProtocol);
            else kLast = 0;
        }
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, _reserves);
        // Test to make sure _reserves is passed by reference and modified by _update()
        if (_feeProtocol >= 0) kLast = _reserves.reserve0 * _reserves.reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        Reserves memory _reserves = getReserves(); // gas savings
        require(amount0Out < _reserves.reserve0 && amount1Out < _reserves.reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        require(to != token0 && to != token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0In = balance0 > _reserves.reserve0 - amount0Out ? balance0 - (_reserves.reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserves.reserve1 - amount1Out ? balance1 - (_reserves.reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0 * FEE_SWAP_PRECISION - amount0In * feeSwap;
        uint balance1Adjusted = balance1 * FEE_SWAP_PRECISION - amount1In * feeSwap;
        require(balance0Adjusted * balance1Adjusted >= _reserves.reserve0 * _reserves.reserve1 * FEE_SWAP_PRECISION**2, 'UniswapV2: K');
        }
        _update(balance0, balance1, _reserves);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        Reserves memory _reserves = getReserves(); // gas savings
        _safeTransfer(token0, to, IERC20(token0).balanceOf(address(this)) - _reserves.reserve0);
        _safeTransfer(token1, to, IERC20(token1).balanceOf(address(this)) - _reserves.reserve1);
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), getReserves());
    }

    function setFeeProtocol(int8 _feeProtocol) external onlyFactory {
        slot0.feeProtocol = _feeProtocol;
        emit SetFeeProtocol(_feeProtocol);
    }
}
