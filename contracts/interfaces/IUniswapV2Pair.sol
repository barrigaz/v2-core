// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;
import './IUniswapV2ERC20.sol';

interface IUniswapV2Pair is IUniswapV2ERC20 {
    struct Reserves {
        uint104 reserve0;
        uint104 reserve1;
        uint32 blockTimestampLast;
    }

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (Reserves memory _reserves);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    function feeSwap() external view returns (uint);
    function feeProtocol() external view returns (int8);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(int8 _feeProtocol) external;
    function setFeeProtocol(int8 _feeProtocol) external;
}
