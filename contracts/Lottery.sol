//SPDX-License-Identifier: Unlicense

pragma solidity 0.5.10;

import "./Ownable.sol";
import "./IERC20.sol";

contract Lottery is Ownable {
    struct Round {
        address payable winner;
        uint256 winningTicket;
        uint256 nextAvailableTicketIndex;
        address token;
        uint256 maximumTicketSupply;
        uint256 maximumTicketAllowedPerUser;
        uint256 winnersShareOutOf1000;
        uint256 unitPrice;
        uint256 startTime;
        uint256 duration;
        address topWallet;
        uint256 topWalletTickets;
        mapping(address => uint256[]) userTickets;
        mapping(uint256 => address payable) ticketOwners;
    }

    bool private _currentRoundIsActive;
    uint256 private _currentRoundId;
    mapping(uint256 => Round) private _roundInfo;
    uint256 private _randNonce;

    event RoundActivated(
        address token,
        uint256 unitPrice,
        uint256 maximumTicketSupply,
        uint256 maximumTicketAllowedPerUser,
        uint256 winnersShareOutOf1000
    );

    event WinnerHasBeenSelected(uint256 roundId, address winner, uint256 winningTicket);

    event WinnerReceivedTheAmount(uint256 currentRoundId, address winner, uint256 winnersShare);

    event TicketSold(address sender, uint256 numberOfTickets);

    event TopWalletChanged(address sender, uint256 tickets);

    modifier roundIsInactive() {
        require(_currentRoundIsActive == false, "Deactivate the latest round first");
        _;
    }

    modifier roundIsActive() {
        require(_currentRoundIsActive == true, "No active round found");
        _;
    }

    modifier hasValue(uint256 parameter) {
        require(parameter > 0, "Passed parameter should be a valid positive number");
        _;
    }

    modifier roundInProgress() {
        require(
            _currentRoundIsActive &&
                block.timestamp > _roundInfo[_currentRoundId].startTime &&
                block.timestamp <
                _roundInfo[_currentRoundId].startTime + _roundInfo[_currentRoundId].duration,
            "Operation not allowed when round is not started"
        );
        _;
    }

    modifier isInFuture(uint256 parameter) {
        require(parameter > block.timestamp, "Parameter expected to be a timestamp in future");
        _;
    }

    constructor() public {
        _currentRoundIsActive = false;
        _currentRoundId = 0;
        _randNonce = 0;
    }

    function startNewRound(
        address token,
        uint256 maximumTicketSupply,
        uint256 maximumTicketAllowedPerUser,
        uint256 winnersShareOutOf1000,
        uint256 unitPrice,
        uint256 startTime,
        uint256 duration
    )
        public
        onlyOwner
        roundIsInactive
        hasValue(maximumTicketSupply)
        hasValue(maximumTicketAllowedPerUser)
        hasValue(winnersShareOutOf1000)
        isInFuture(startTime)
        hasValue(duration)
    {
        uint256 newRoundId = _currentRoundId + 1;
        _roundInfo[newRoundId] = Round({
            winner: address(0),
            winningTicket: 0,
            nextAvailableTicketIndex: 0,
            token: token,
            maximumTicketSupply: maximumTicketSupply,
            maximumTicketAllowedPerUser: maximumTicketAllowedPerUser,
            unitPrice: unitPrice,
            winnersShareOutOf1000: winnersShareOutOf1000,
            startTime: startTime,
            duration: duration,
            topWallet: address(0),
            topWalletTickets: 0
        });

        _currentRoundId = newRoundId;
        _currentRoundIsActive = true;

        emit RoundActivated(
            token,
            unitPrice,
            maximumTicketSupply,
            maximumTicketAllowedPerUser,
            winnersShareOutOf1000
        );
    }

    function finalizeTheRound() public onlyOwner roundIsActive {
        _currentRoundIsActive = false;

        _findTheWinner();
        if (_roundInfo[_currentRoundId].token == address(0)) {
            _payShares(_roundInfo[_currentRoundId].winner, _roundInfo[_currentRoundId].winnersShareOutOf1000);
        } else {
            _paySharesERC20(
                _roundInfo[_currentRoundId].token,
                _roundInfo[_currentRoundId].winner,
                _roundInfo[_currentRoundId].winnersShareOutOf1000
            );
        }
    }

    function _payShares(address payable winner, uint256 winnersShareOutOf1000) internal {
        require(address(this).balance > 0, "Contract balance is not enough");
        uint256 winnersShare = (address(this).balance * winnersShareOutOf1000) / 1000;
        winner.transfer(winnersShare);
        msg.sender.transfer(address(this).balance);
        emit WinnerReceivedTheAmount(_currentRoundId, winner, winnersShare);
    }

    function _paySharesERC20(
        address token,
        address payable winner,
        uint256 winnersShareOutOf1000
    ) internal {
        IERC20 _token = IERC20(token);
        require(_token.balanceOf(address(this)) > 0, "Contract balance is not enough");
        uint256 winnersShare = (_token.balanceOf(address(this)) * winnersShareOutOf1000) / 1000;
        _token.transfer(winner, winnersShare);
        _token.transfer(msg.sender, winnersShare);
        emit WinnerReceivedTheAmount(_currentRoundId, winner, winnersShare);
    }

    function _findTheWinner() internal {
        require(
            _roundInfo[_currentRoundId].nextAvailableTicketIndex > 0,
            "At least one participant is required"
        );
        _roundInfo[_currentRoundId].winningTicket = getRandom(
            _roundInfo[_currentRoundId].nextAvailableTicketIndex
        );
        _roundInfo[_currentRoundId].winner = _roundInfo[_currentRoundId].ticketOwners[
            _roundInfo[_currentRoundId].winningTicket
        ];

        emit WinnerHasBeenSelected(
            _currentRoundId,
            _roundInfo[_currentRoundId].winner,
            _roundInfo[_currentRoundId].winningTicket
        );
    }

    function getRandom(uint256 modulus) internal returns (uint256) {
        _randNonce++;
        return uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, _randNonce))) % modulus;
    }

    function buyTicket() public payable roundInProgress {
        if (_roundInfo[_currentRoundId].token == address(0)) {
            require(
                msg.value > 0 && (msg.value % _roundInfo[_currentRoundId].unitPrice == 0),
                "Transfered amount is not valid"
            );
        } else {
            require(msg.value == 0, "ERC20 token is required for this round");
        }

        uint256 allowedNumberOfTickets = _roundInfo[_currentRoundId].maximumTicketAllowedPerUser;
        allowedNumberOfTickets =
            allowedNumberOfTickets -
            _roundInfo[_currentRoundId].userTickets[msg.sender].length;
        uint256 requestedTickets = msg.value / _roundInfo[_currentRoundId].unitPrice;

        require(requestedTickets <= allowedNumberOfTickets, "User limit has been reached to buy new tickets");

        uint256 remainingTickets = _roundInfo[_currentRoundId].maximumTicketSupply -
            _roundInfo[_currentRoundId].nextAvailableTicketIndex -
            requestedTickets;

        require(requestedTickets <= remainingTickets, "Maximum ticket supply exceeded");

        if (_roundInfo[_currentRoundId].token == address(0)) {
            _buyTicket(msg.sender, requestedTickets);
        } else {
            _buyTicketERC20(_roundInfo[_currentRoundId].token, msg.sender, requestedTickets);
        }

        emit TicketSold(msg.sender, requestedTickets);

        if (
            _roundInfo[_currentRoundId].userTickets[msg.sender].length >
            _roundInfo[_currentRoundId].topWalletTickets
        ) {
            _roundInfo[_currentRoundId].topWalletTickets = _roundInfo[_currentRoundId]
                .userTickets[msg.sender]
                .length;
            _roundInfo[_currentRoundId].topWallet = msg.sender;
            emit TopWalletChanged(msg.sender, _roundInfo[_currentRoundId].topWalletTickets);
        }
    }

    function _buyTicket(address payable sender, uint256 numberOfTickets) internal {
        for (uint256 i = 0; i < numberOfTickets; i++) {
            _roundInfo[_currentRoundId].userTickets[msg.sender].push(
                _roundInfo[_currentRoundId].nextAvailableTicketIndex
            );
            _roundInfo[_currentRoundId].ticketOwners[
                _roundInfo[_currentRoundId].nextAvailableTicketIndex
            ] = sender;

            _roundInfo[_currentRoundId].nextAvailableTicketIndex++;
        }
    }

    function _buyTicketERC20(
        address token,
        address payable sender,
        uint256 numberOfTickets
    ) internal {
        IERC20 _token = IERC20(token);
        uint256 amount = _roundInfo[_currentRoundId].unitPrice * numberOfTickets;
        uint256 allowance = _token.allowance(sender, address(this));
        require(allowance == amount, "Check the token allowance");
        _token.transferFrom(sender, address(this), amount);

        _buyTicket(sender, numberOfTickets);
    }

    function getTopWallet() public view roundIsActive returns (address topWallet, uint256[] memory tickets) {
        return (
            _roundInfo[_currentRoundId].topWallet,
            _roundInfo[_currentRoundId].userTickets[_roundInfo[_currentRoundId].topWallet]
        );
    }

    // Can anyone see the ticket list of others?
    function getWalletTickets(address wallet) public view roundIsActive returns (uint256[] memory tickets) {
        return _roundInfo[_currentRoundId].userTickets[wallet];
    }

    function getWinner() public view roundIsActive returns (address winner, uint256 winningTicket) {
        return (_roundInfo[_currentRoundId].winner, _roundInfo[_currentRoundId].winningTicket);
    }

    function getStartDuration() public view roundIsActive returns (uint256 startTime, uint256 duration) {
        return (_roundInfo[_currentRoundId].startTime, _roundInfo[_currentRoundId].duration);
    }

    function getPaymentInfo() public view roundIsActive returns (address token, uint256 unitPrice) {
        return (_roundInfo[_currentRoundId].token, _roundInfo[_currentRoundId].unitPrice);
    }

    function getTicketSupplyInfo()
        public
        view
        roundIsActive
        returns (
            uint256 maximumSupply,
            uint256 nextAvailableTicket,
            uint256 userMaxTickets
        )
    {
        return (
            _roundInfo[_currentRoundId].maximumTicketSupply,
            _roundInfo[_currentRoundId].nextAvailableTicketIndex,
            _roundInfo[_currentRoundId].maximumTicketAllowedPerUser
        );
    }

    function forciblyDeactivateRound() public onlyOwner {
        _currentRoundIsActive = false;
    }

    function getRoundInfo() public view returns (uint256, bool) {
        return (_currentRoundId, _currentRoundIsActive);
    }
}
