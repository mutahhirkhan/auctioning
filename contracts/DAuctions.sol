// SPDX-License-Identifier: MIT
/**
 * Problem:
You are tasked with designing a smart contract that implements a decentralized auction platform on
Ethereum. The platform should allow users to bid on items and should automatically process the
winning bids at the end of the auction.

The smart contract should have the following functionalities:

Users can create new auctions by specifying the auction end time, minimum bid amount, and item
description.
Users can place bids on an auction.
The highest bid should be displayed for each auction.
When the auction ends, the highest bidder should be declared the winner, and the winning bid amount
should be transferred to the seller's account.
The winning bidder should be able to claim the item after the payment has been made.
If the auction ends without any bids, the seller should be able to retrieve the item.

You should also consider all security concerns.

Finally, explain how you would ensure scalability for this platform and what scalability solutions you
would consider.

Please provide the Solidity code for the smart contract (and unit tests if possible) , a brief explanation of
your implementation choices, and a description of how you addressed the security concerns and
scalability issues.

Any steps taken to optimize gas fee will be highly appreciated

Feel free to ask any question.
 */

pragma solidity 0.8.19;
import "hardhat/console.sol";

interface IERC721 {
    function transferFrom(address from, address to, uint tokenId) external;

    function approve(address to, uint tokenId) external;

    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);

    function safeTransferFrom(address from, address to, uint tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// Definition of custom errors
error OnAuction();
error BidTooLow();
error LessAmount();
error ZeroAddress();
error NotApproved();
error AuctionEnded();
error CallerNotOwner();
error InvalidEndTime();

contract DAuctions {
    //bool and address will go into single slot
    //rest wil ltake single slot each
    struct Auction {
        bool ended;
        address seller;
        uint endTime;
        uint minBid;
        uint tokenId;
        uint highestBid;
        address tokenAddress;
        address payable highestBidder;
        string itemDescription;
    }

    // user all bids
    struct Bid {
        uint auctionId;
        uint bidAmount;
    }

    //auction id to bid id to bi info
    mapping(address => Bid[]) public userBid;

    // auction id to auction info
    mapping(uint => Auction) public auctions;

    uint public auctionCount;

    event NewAuction(
        uint auctionId,
        string description,
        address indexed seller,
        uint auctionEndTime,
        uint minBid
    );
    event NewBid(uint auctionId, address indexed bidder, uint bidAmount);
    event AuctionEnd(uint auctionId, address indexed winner, uint highestBid); //bid claimed
    event AuctionRevoked(uint auctionId, address indexed seller);

    function putOnAuction(
        string calldata _itemDescription,
        uint _endTime,
        uint _minBid,
        address _tokenAddress,
        uint _tokenId
    ) external {
        if (_endTime > block.timestamp) revert InvalidEndTime();
        if (_minBid == 0) revert LessAmount();

        if (_tokenAddress == address(0)) revert ZeroAddress();

        //check approval of NFT and pull item from user
        if (!IERC721(_tokenAddress).isApprovedForAll(msg.sender, address(this)))
            revert NotApproved();

        //check if item is already on auction
        //if owner is alreayd this contract, then item is on auction or someone sent item to this contract
        //and becuase it is sent forcibly, then this auction would have no amount backed by it to facilitate bider
        if (IERC721(_tokenAddress).ownerOf(_tokenId) == address(this))
            revert OnAuction();

        IERC721(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );



        //create auction
        auctionCount++;

        auctions[auctionCount] = Auction({
            seller: msg.sender,
            endTime: _endTime,
            itemDescription: _itemDescription,
            minBid: _minBid,
            tokenAddress: _tokenAddress,
            tokenId: _tokenId,
            highestBidder: payable(address(0)),
            highestBid: 0,
            ended: false
        });
        emit NewAuction(
            auctionCount,
            _itemDescription,
            msg.sender,
            _endTime,
            _minBid
        );
    }

    function placeBid(uint _auctionId) external payable {
        uint _msgValue = msg.value;
        Auction storage selectedAuction = auctions[_auctionId];
        //check if auction is ended
        //also ensures for invalid auction ids
        if (selectedAuction.endTime < block.timestamp) revert AuctionEnded();

        //revert if the bid is lesser than (the highest bid or min bid)
        //there is no point of making a bid lower than highest bid
        if (
            _msgValue < selectedAuction.minBid &&
            _msgValue < selectedAuction.highestBid
        ) revert BidTooLow();

        //current bid is higher than highest bid
        if (_msgValue > selectedAuction.highestBid) {
            //update highest bid
            selectedAuction.highestBid = _msgValue;
            selectedAuction.highestBidder = payable(msg.sender);

            //refund previous highest bidder
            (bool sent, ) = (selectedAuction.highestBidder).call{
                value: selectedAuction.highestBid
            }("");
            require(sent, "ETH_FAILED");
        }

        //add bid to user bid
        userBid[msg.sender].push(
            Bid({auctionId: _auctionId, bidAmount: _msgValue})
        );
        emit NewBid(_auctionId, msg.sender, _msgValue);
    }

    //callable by both seller and the highest bidder
    function claimBid(uint auctionId) external {
        //loading in storage to save gas
        Auction storage selectedAuction = auctions[auctionId];

        //check if auction is ended
        if (selectedAuction.endTime < block.timestamp) revert OnAuction();

        //check if caller is the highest bidder or seller
        if (
            msg.sender == selectedAuction.highestBidder ||
            msg.sender == selectedAuction.highestBidder
        ) {
            //update auction status
            selectedAuction.ended = true;

            //transfer item to highest bidder
            IERC721(selectedAuction.tokenAddress).safeTransferFrom(
                address(this),
                selectedAuction.highestBidder,
                selectedAuction.tokenId
            );

            //transfer highest bid to seller
            (bool sent, ) = (selectedAuction.highestBidder).call{
                value: selectedAuction.highestBid
            }("");
            require(sent, "ETH_FAILED");
        }
        emit AuctionEnd(
            auctionId,
            selectedAuction.highestBidder,
            selectedAuction.highestBid
        );
    }

    function putOffAuction(uint _auctionId) external {
        Auction storage selectedAuction = auctions[_auctionId];
        //check if caller is the owner
        if (selectedAuction.seller != msg.sender) revert CallerNotOwner();

        //check if auction is ended
        if (selectedAuction.endTime < block.timestamp) revert AuctionEnded();

        //update auction status
        selectedAuction.ended = true;

        //transfer item to seller
        IERC721(selectedAuction.tokenAddress).safeTransferFrom(
            address(this),
            selectedAuction.seller,
            selectedAuction.tokenId
        );
        emit AuctionRevoked(_auctionId, selectedAuction.seller);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // Add your implementation here
        return this.onERC721Received.selector;
    }
}
