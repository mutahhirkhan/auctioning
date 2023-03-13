const { expect } = require("chai");
const { createFixtureLoader } = require("ethereum-waffle");
const { ethers } = require("hardhat");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

describe("Decentralized Auction", () => {
	const DESCRIPTION = "DESCRIPTION";
	const MIN_BID = ethers.utils.parseEther("0.1");
	const MAX_UINT = ethers.constants.MaxUint256;
	const ZERO_ADDRESS = ethers.constants.AddressZero;
	const DAY = 86400;

 const ERRORS = {
  OnAuction: 'OnAuction()',
  BidTooLow: 'BidTooLow()',
  LessAmount: 'LessAmount()',
  ZeroAddress: 'ZeroAddress()',
  NotApproved: 'NotApproved()',
  AuctionEnded: 'AuctionEnded()',
  CallerNotOwner: 'CallerNotOwner()',
  InvalidEndTime: 'InvalidEndTime()',
 }

	let loadFixture;
	let owner, alice, bob, carol;
	let erc721, TOKEN_ADDRESS;

	before(async () => {
		// /extract signers from ethers
		const myWallets = await ethers.getSigners();
		loadFixture = createFixtureLoader(myWallets);
		[owner, alice, bob, carol] = myWallets;

		const ERC721_MINIMAL = await ethers.getContractFactory("MinimalERC721");
		erc721 = await ERC721_MINIMAL.connect(owner).deploy();
		await erc721.deployed();
		console.log("ERC721 deployed to:", (TOKEN_ADDRESS = erc721.address), "by", owner.address);
	});

	async function fixture([wallet], provider) {
		const DAuctions = await ethers.getContractFactory("DAuctions");
		const dauctions = await DAuctions.deploy();
		await dauctions.deployed();
		console.log("DAuctions deployed to:", dauctions.address, "by", wallet.address);

		//give all 10 tokens approval to the dauction contract
		await erc721.connect(owner).setApprovalForAll(dauctions.address, true);

		return { dauctions, wallet };
	}

	describe("pre-testing checks", () => {
		it("check contract deployment", async () => {
			const { dauctions, wallet } = await loadFixture(fixture);
			expect(await dauctions.address).not.to.be.undefined;
			expect(await dauctions.address).not.to.be.null;
		});
		it("check max approval", async () => {
			const { dauctions, wallet } = await loadFixture(fixture);
			erc721
				.connect(owner)
				.isApprovedForAll(owner.address, dauctions.address)
				.then((res) => {
					expect(res).to.equal(true);
				});
		});
	});

	describe("putOnAuction", () => {
		it("should put an item on auction", async () => {
			const { dauctions } = await loadFixture(fixture);
			await dauctions.connect(owner).putOnAuction(DESCRIPTION, DAY, MIN_BID, TOKEN_ADDRESS, 1);
			expect(await dauctions.auctionCount()).to.equal(1);
			expect(await erc721.ownerOf(1)).to.equal(dauctions.address);
		});

		it("should put unminted item on sell", async () => {
			const { dauctions } = await loadFixture(fixture);
			//non existent token id
			expect(dauctions.connect(owner).putOnAuction(DESCRIPTION, DAY, MIN_BID, TOKEN_ADDRESS, 101)).to.be.revertedWith(
				"ERC721: invalid token ID"
			);
		});

		xit("should not let to put on auction again the same item", async () => {
			const { dauctions } = await loadFixture(fixture);
			await dauctions.connect(owner).putOnAuction(DESCRIPTION, DAY, MIN_BID, TOKEN_ADDRESS, 1);
			await expect(dauctions.connect(owner).putOnAuction(DESCRIPTION, DAY, MIN_BID, TOKEN_ADDRESS, 1)).to.be.revertedWith(`OnAuction`);
		});

	});
});
