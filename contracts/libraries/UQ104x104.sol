// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))

// range: [0, 2**104 - 1]
// resolution: 1 / 2**104

library UQ104x104 {
    uint208 constant Q104 = 2**104;

    // encode a uint104 as a UQ104x104
    function encode(uint104 y) internal pure returns (uint208 z) {
        z = uint208(y) * Q104; // never overflows
    }

    // divide a UQ104x104 by a uint104, returning a UQ104x104
    function uqdiv(uint208 x, uint104 y) internal pure returns (uint208 z) {
        z = x / uint208(y);
    }
}
