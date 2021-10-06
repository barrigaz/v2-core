// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    uint private constant FEE_SWAP_PRECISION = 10**5;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    ReservesSlot private reservesSlot; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // pair swap fee as parts per FEE_SWAP_PRECISION
    uint120 public feeSwap;
    // pair protocol fee as a percentage of the swap fee in form simple fracton:
    // negative - fees turned off, 0 - 1, 1 - 1/2, 2 - 1/3, 3 - 1/4 etc
    int120 public feeProtocol;
    // reenterance lock
    uint16 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() external view returns (ReservesSlot memory _reservesSlot) {
        return reservesSlot;
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
    event Sync(uint112 reserve0, uint112 reserve1);
    event SetFeeProtocol(int120 feeProtocol);

    modifier onlyFactory() {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN');
        _;
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1, uint120 _feeSwap, int120 _feeProtocol) external onlyFactory {
        token0 = _token0;
        token1 = _token1;
        feeSwap = _feeSwap;
        feeProtocol = _feeProtocol;
        emit SetFeeProtocol(_feeProtocol);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, ReservesSlot memory _reservesSlot) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'UniswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - _reservesSlot.blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reservesSlot.reserve0 != 0 && _reservesSlot.reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += UQ112x112.encode(_reservesSlot.reserve1).uqdiv(_reservesSlot.reserve0) * timeElapsed;
            price1CumulativeLast += UQ112x112.encode(_reservesSlot.reserve0).uqdiv(_reservesSlot.reserve1) * timeElapsed;
        }
        reservesSlot.reserve0 = _reservesSlot.reserve0 = uint112(balance0);
        reservesSlot.reserve1 = _reservesSlot.reserve1 = uint112(balance1);
        reservesSlot.blockTimestampLast = blockTimestamp;
        emit Sync(_reservesSlot.reserve0, _reservesSlot.reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/(feeProtocol+1)th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1, uint _kLast, int120 _feeProtocol) private {
        uint rootK = Math.sqrt(_reserve0 * _reserve1);
        uint rootKLast = Math.sqrt(_kLast);
        if (rootK > rootKLast) {
            uint numerator = totalSupply * (rootK - rootKLast);
            uint denominator = rootK * uint120(_feeProtocol) + rootKLast;
            uint liquidity = numerator / denominator;
            if (liquidity > 0) {
                _mint(IUniswapV2Factory(factory).feeTo(), liquidity);
            }
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        ReservesSlot memory _reservesSlot = reservesSlot; // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reservesSlot.reserve0;
        uint amount1 = balance1 - _reservesSlot.reserve1;

        uint _kLast = kLast; // gas savings
        int120 _feeProtocol = feeProtocol; // gas savings
        if (_kLast != 0) {
            if (_feeProtocol >= 0) _mintFee(_reservesSlot.reserve0, _reservesSlot.reserve1, _kLast, _feeProtocol);
            else kLast = 0;
        }
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1 - MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reservesSlot.reserve0, amount1 * _totalSupply / _reservesSlot.reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reservesSlot);
        // Test to make sure _reservesSlot is passed by reference and modified by _update()
        if (_feeProtocol >= 0) kLast = _reservesSlot.reserve0 * _reservesSlot.reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        ReservesSlot memory _reservesSlot = reservesSlot; // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        uint _kLast = kLast; // gas savings
        int120 _feeProtocol = feeProtocol; // gas savings
        if (_kLast != 0) {
            if (_feeProtocol >= 0) _mintFee(_reservesSlot.reserve0, _reservesSlot.reserve1, _kLast, _feeProtocol);
            else kLast = 0;
        }
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reservesSlot);
        // Test to make sure _reservesSlot is passed by reference and modified by _update()
        if (_feeProtocol >= 0) kLast = _reservesSlot.reserve0 * _reservesSlot.reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        ReservesSlot memory _reservesSlot = reservesSlot; // gas savings
        require(amount0Out < _reservesSlot.reserve0 && amount1Out < _reservesSlot.reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reservesSlot.reserve0 - amount0Out ? balance0 - (_reservesSlot.reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reservesSlot.reserve1 - amount1Out ? balance1 - (_reservesSlot.reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint _feeSwap = feeSwap; // gas savings
        uint balance0Adjusted = balance0 * FEE_SWAP_PRECISION - amount0In * _feeSwap;
        uint balance1Adjusted = balance1 * FEE_SWAP_PRECISION - amount1In * _feeSwap;
        require(balance0Adjusted * balance1Adjusted >= _reservesSlot.reserve0 * _reservesSlot.reserve1 * FEE_SWAP_PRECISION**2, 'UniswapV2: K');
        }
        _update(balance0, balance1, _reservesSlot);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        ReservesSlot memory _reservesSlot = reservesSlot; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - _reservesSlot.reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - _reservesSlot.reserve1);
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reservesSlot);
    }

    function setFeeProtocol(int120 _feeProtocol) external onlyFactory {
        feeProtocol = _feeProtocol;
        emit SetFeeProtocol(_feeProtocol);
    }
}
