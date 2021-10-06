// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public owner;

    mapping(address => mapping(address => mapping(uint120 => address))) private pairs;
    address[] public allPairs;
    int120 public fee;

    event PairCreated(address indexed token0, address indexed token1, uint120 feeSwap, address pair, uint);

    modifier onlyOwner() {
        require(msg.sender == owner, 'UniswapV2: FORBIDDEN');
        _;
    }

    constructor(address _owner, int120 _fee) {
        owner = _owner;
        fee = _fee;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB, uint120 feeSwap) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(tokenA != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(pairs[tokenA][tokenB][feeSwap] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB, feeSwap));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(tokenA, tokenB, feeSwap, fee);
        pairs[tokenA][tokenB][feeSwap] = pair;
        allPairs.push(pair);
        emit PairCreated(tokenA, tokenB, feeSwap, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }

    function setFee(int120 _fee) external onlyOwner {
        fee = _fee;
    }

    function setFeeProtocolPair(address pair, int120 feeProtocol) external onlyOwner {
        IUniswapV2Pair(pair).setFeeProtocol(feeProtocol);
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function getPair(address tokenA, address tokenB, uint120 feeSwap) external view returns(address) {
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return pairs[tokenA][tokenB][feeSwap];
    }

}
