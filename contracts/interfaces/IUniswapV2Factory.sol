// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

interface IUniswapV2Factory {
    function feeTo() external view returns (address);
    function fee() external view returns (int8);
    function owner() external view returns (address);

    function getPair(address tokenA, address tokenB, uint feeSwap) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB, uint feeSwap) external returns (address pair);

    function setFeeTo(address _feeTo) external;
    function setFee(int8 _fee) external;
    function setFeeProtocolPair(address pair, int8 feeProtocol) external;
    function setOwner(address _owner) external;
}
