// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

interface IUniswapV2Pair {
    struct ReservesSlot {
        uint112 reserve0;           
        uint112 reserve1;
        uint32 blockTimestampLast;
    }

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (ReservesSlot memory _reservesSlot);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    function feeSwap() external view returns (uint120);
    function feeProtocol() external view returns (int120);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address _token0, address _token1, uint120 _feeSwap, int120 _feeProtocol) external;
    function setFeeProtocol(int120 _feeProtocol) external;
}
