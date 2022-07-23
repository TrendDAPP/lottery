// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/ILottery.sol";
import "@chainlink/contracts/src/v0.8/dev/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelinUpgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelinUpgradeable/contracts/proxy/utils/Initializable.sol";

/// @dev The winner will be chosen with a random number generated by Chainlink
contract Lottery is
    ILottery,
    Initializable,
    OwnableUpgradeable,
    VRFConsumerBaseV2(0x6168499c0cFfCaCD319c818142124B7A15E857ab)
{
    // Rinkeby testnet configurations
    VRFCoordinatorV2Interface constant COORDINATOR =
        VRFCoordinatorV2Interface(0x6168499c0cFfCaCD319c818142124B7A15E857ab);
    bytes32 constant KEY_HASH =
        0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
    uint64 constant SUBSCRIPTION_ID = 247; // https://vrf.chain.link
    uint32 constant CALLBACK_GAS_LIMIT = 1000000;
    uint32 constant NUM_WORDS = 1;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint256[] randomWords;
    uint256 requestId;

    /// @inheritdoc ILottery
    uint256 public override lotteryID;
    /// @inheritdoc ILottery
    address[] public override participants;
    /// @inheritdoc ILottery
    uint256 public override costPerTicket;
    /// @inheritdoc ILottery
    uint256 public override prizePool;
    /// @inheritdoc ILottery
    uint256 public override startingTimestamp;
    /// @inheritdoc ILottery
    address public override winner;
    /// @inheritdoc ILottery
    uint256 public override randomResult;
    /// @inheritdoc ILottery
    uint256 public override lotteryDuration;
    /// @inheritdoc ILottery
    uint8 public override winnerPercentage;
    /// @inheritdoc ILottery
    Status public override lotteryStatus = Status.NOT_STARTED;

    struct LotteryInfo {
        uint256 lotteryID;
        uint256 prizePool;
        uint256 costPerTicket;
        uint256 startingTimestamp;
        address winner;
        uint256 randomNumber;
    }
    /// @inheritdoc ILottery
    mapping(uint256 => LotteryInfo) public override allLotteries;

    modifier canClose() {
        require(
            lotteryStatus == Status.OPEN,
            "You can not close the unstarted lottery!"
        );
        require(
            block.timestamp >= startingTimestamp + lotteryDuration,
            "Time is not over!"
        );
        require(randomResult == 0, "The lottery is already closed!"); // to prevent re-closing
        _;
    }

    modifier ifNotStarted() {
        require(lotteryStatus == Status.NOT_STARTED);
        _;
    }

    modifier ifOpen() {
        require(
            lotteryStatus == Status.OPEN,
            "The lottery has not started yet!"
        );
        require(
            block.timestamp <= startingTimestamp + lotteryDuration,
            "Time is over!"
        );
        _;
    }

    modifier ifCompleted() {
        require(
            lotteryStatus == Status.COMPLETED,
            "The lottery has not completed yet!"
        );
        _;
    }

    modifier onlyWinnerOrOwner() {
        require(
            msg.sender == winner || msg.sender == owner(),
            "Only the winner can claim reward!"
        );
        _;
    }

    modifier randomNumberGenerated() {
        require(winner != address(0), "The winner has not been selected!");
        _;
    }

    // constructor
    function initialize() external initializer {
        __Ownable_init();
    }

    /// @inheritdoc ILottery
    function startLottery(
        uint256 _ticketPrice,
        uint8 _winnerPercentage,
        uint256 _lotteryDuration
    ) external override ifNotStarted onlyOwner {
        lotteryStatus = Status.OPEN;
        costPerTicket = _ticketPrice;
        winnerPercentage = _winnerPercentage;
        lotteryDuration = _lotteryDuration;
        startingTimestamp = block.timestamp;
        emit OpenedLottery(lotteryID);
    }

    /// @inheritdoc ILottery
    function buyTicket() external payable override ifOpen {
        require(msg.value == costPerTicket, "Enter a valid price!");
        prizePool += costPerTicket;
        participants.push(payable(msg.sender));
    }

    /// @inheritdoc ILottery
    function closeLottery() external override canClose onlyOwner {
        if (participants.length != 0) {
            lotteryStatus = Status.CLOSED;
            _requestRandomWords();
            emit RequestedRandomWords(requestId);
            emit ClosedLottery(lotteryID);
        } else {
            _addLottery();
            _reset();
            emit ClosedLottery(lotteryID);
            emit CompletedLottery(lotteryID);
        }
    }

    /// @inheritdoc ILottery
    function claimReward()
        external
        override
        ifCompleted
        randomNumberGenerated
        onlyWinnerOrOwner
    {
        _addLottery();
        uint256 winnerPrize_ = (prizePool * winnerPercentage) / 100;
        address winner_ = winner;
        _reset();
        _transferPrize(winner_, winnerPrize_);
        emit ClaimedReward(lotteryID);
    }

    /// @inheritdoc ILottery
    function withdrawEth() external override onlyOwner {
        require(prizePool == 0, "The prizePool is not empty!");
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to withdraw!");
    }

    function fulfillRandomWords(uint256, uint256[] memory _randomWords)
        internal
        override
    {
        lotteryStatus = Status.COMPLETED;
        randomWords = _randomWords;
        randomResult = randomWords[0];
        winner = participants[randomResult % participants.length];
        emit CompletedLottery(lotteryID);
    }

    function _requestRandomWords() private onlyOwner {
        requestId = COORDINATOR.requestRandomWords(
            KEY_HASH,
            SUBSCRIPTION_ID,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );
    }

    function _transferPrize(address _winner, uint256 _winnerPrize) private {
        (bool sent, ) = _winner.call{value: _winnerPrize}("");
        require(sent, "Failed to send winner prize!");
    }

    function _addLottery() private {
        allLotteries[lotteryID++] = LotteryInfo(
            lotteryID,
            prizePool,
            costPerTicket,
            startingTimestamp,
            winner,
            randomResult
        );
    }

    function _reset() private {
        lotteryStatus = Status.NOT_STARTED;
        costPerTicket = 0;
        lotteryDuration = 0;
        participants = new address payable[](0);
        prizePool = 0;
        randomResult = 0;
        startingTimestamp = 0;
        winner = payable(address(0));
    }
}
