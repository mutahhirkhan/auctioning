//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MinimalERC721 is ERC721 {
    constructor() ERC721("Minimal", "MIN") {
     for(uint i = 0; i < 100; i++) {
      _mint(msg.sender, i);
     }
    }
}