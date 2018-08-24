
// Copyright (C) 2017-2018  MixBytes, LLC

// Licensed under the Apache License, Version 2.0 (the "License").
// You may not use this file except in compliance with the License.

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND (express or implied).

// Code taken from https://github.com/ethereum/dapp-bin/blob/master/wallet/wallet.sol
// Audit, refactoring and improvements by github.com/Eenae


pragma solidity ^0.4.15;

contract multiowned {

    struct MultiOwnedOperationPendingState {

        uint yetNeeded;

        uint ownersDone;

        uint index;
    }

    event Confirmation(address owner, bytes32 operation);
    event Revoke(address owner, bytes32 operation);
    event FinalConfirmation(address owner, bytes32 operation);
    event OwnerChanged(address oldOwner, address newOwner);
    event OwnerAdded(address newOwner);
    event OwnerRemoved(address oldOwner);
    event RequirementChanged(uint newRequirement);

    modifier onlyowner {
        require(isOwner(msg.sender));
        _;
    }

    modifier onlymanyowners(bytes32 _operation) {
        if (confirmAndCheck(_operation)) {
            _;
        }
    }

    modifier validNumOwners(uint _numOwners) {
        require(_numOwners > 0 && _numOwners <= c_maxOwners);
        _;
    }

    modifier multiOwnedValidRequirement(uint _required, uint _numOwners) {
        require(_required > 0 && _required <= _numOwners);
        _;
    }

    modifier ownerExists(address _address) {
        require(isOwner(_address));
        _;
    }

    modifier ownerDoesNotExist(address _address) {
        require(!isOwner(_address));
        _;
    }

    modifier multiOwnedOperationIsActive(bytes32 _operation) {
        require(isOperationActive(_operation));
        _;
    }

	// METHODS
	// @notice multi owned
    function multiowned(address[] _owners, uint _required)
        public
        validNumOwners(_owners.length)
        multiOwnedValidRequirement(_required, _owners.length)
    {
        assert(c_maxOwners <= 255);

        m_numOwners = _owners.length;
        m_multiOwnedRequired = _required;

        for (uint i = 0; i < _owners.length; ++i)
        {
            address owner = _owners[i];
            // invalid and duplicate addresses are not allowed
            require(0 != owner && !isOwner(owner) /* not isOwner yet! */);

            uint currentOwnerIndex = checkOwnerIndex(i + 1 /* first slot is unused */);
            m_owners[currentOwnerIndex] = owner;
            m_ownerIndex[owner] = currentOwnerIndex;
        }

        assertOwnersAreConsistent();
    }

	// @notice change owner
    function changeOwner(address _from, address _to)
        external
        ownerExists(_from)
        ownerDoesNotExist(_to)
        onlymanyowners(keccak256(msg.data))
    {
        assertOwnersAreConsistent();

        clearPending();
        uint ownerIndex = checkOwnerIndex(m_ownerIndex[_from]);
        m_owners[ownerIndex] = _to;
        m_ownerIndex[_from] = 0;
        m_ownerIndex[_to] = ownerIndex;

        assertOwnersAreConsistent();
        OwnerChanged(_from, _to);
    }

    // @notice adds an owner
    function addOwner(address _owner)
        external
        ownerDoesNotExist(_owner)
        validNumOwners(m_numOwners + 1)
        onlymanyowners(keccak256(msg.data))
    {
        assertOwnersAreConsistent();

        clearPending();
        m_numOwners++;
        m_owners[m_numOwners] = _owner;
        m_ownerIndex[_owner] = checkOwnerIndex(m_numOwners);

        assertOwnersAreConsistent();
        OwnerAdded(_owner);
    }

    /// @notice removes an owner
    function removeOwner(address _owner)
        external
        ownerExists(_owner)
        validNumOwners(m_numOwners - 1)
        multiOwnedValidRequirement(m_multiOwnedRequired, m_numOwners - 1)
        onlymanyowners(keccak256(msg.data))
    {
        assertOwnersAreConsistent();

        clearPending();
        uint ownerIndex = checkOwnerIndex(m_ownerIndex[_owner]);
        m_owners[ownerIndex] = 0;
        m_ownerIndex[_owner] = 0;
    
        reorganizeOwners();

        assertOwnersAreConsistent();
        OwnerRemoved(_owner);
    }

    // @notice changes the required number of owner signatures
    function changeRequirement(uint _newRequired)
        external
        multiOwnedValidRequirement(_newRequired, m_numOwners)
        onlymanyowners(keccak256(msg.data))
    {
        m_multiOwnedRequired = _newRequired;
        clearPending();
        RequirementChanged(_newRequired);
    }

    // @notice Gets an owner by 0-indexed position
    function getOwner(uint ownerIndex) public constant returns (address) {
        return m_owners[ownerIndex + 1];
    }

    // @notice Gets owners
    function getOwners() public constant returns (address[]) {
        address[] memory result = new address[](m_numOwners);
        for (uint i = 0; i < m_numOwners; i++)
            result[i] = getOwner(i);

        return result;
    }

    // @notice checks if provided address is an owner address
    function isOwner(address _addr) public constant returns (bool) {
        return m_ownerIndex[_addr] > 0;
    }

    // @notice Tests ownership of the current caller.
    function amIOwner() external constant onlyowner returns (bool) {
        return true;
    }

    // @notice Revokes a prior confirmation of the given operation
    function revoke(bytes32 _operation)
        external
        multiOwnedOperationIsActive(_operation)
        onlyowner
    {
        uint ownerIndexBit = makeOwnerBitmapBit(msg.sender);
        var pending = m_multiOwnedPending[_operation];
        require(pending.ownersDone & ownerIndexBit > 0);

        assertOperationIsConsistent(_operation);

        pending.yetNeeded++;
        pending.ownersDone -= ownerIndexBit;

        assertOperationIsConsistent(_operation);
        Revoke(msg.sender, _operation);
    }

    // @notice Checks if owner confirmed given operation
    function hasConfirmed(bytes32 _operation, address _owner)
        external
        constant
        multiOwnedOperationIsActive(_operation)
        ownerExists(_owner)
        returns (bool)
    {
        return !(m_multiOwnedPending[_operation].ownersDone & makeOwnerBitmapBit(_owner) == 0);
    }

    // INTERNAL METHODS

    function confirmAndCheck(bytes32 _operation)
        private
        onlyowner
        returns (bool)
    {
        if (512 == m_multiOwnedPendingIndex.length)
            clearPending();

        var pending = m_multiOwnedPending[_operation];

        if (! isOperationActive(_operation)) {
            pending.yetNeeded = m_multiOwnedRequired;
            pending.ownersDone = 0;
            pending.index = m_multiOwnedPendingIndex.length++;
            m_multiOwnedPendingIndex[pending.index] = _operation;
            assertOperationIsConsistent(_operation);
        }

    
        uint ownerIndexBit = makeOwnerBitmapBit(msg.sender);
        if (pending.ownersDone & ownerIndexBit == 0) {
            assert(pending.yetNeeded > 0);
            if (pending.yetNeeded == 1) {
                delete m_multiOwnedPendingIndex[m_multiOwnedPending[_operation].index];
                delete m_multiOwnedPending[_operation];
                FinalConfirmation(msg.sender, _operation);
                return true;
            }
            else
            {
                pending.yetNeeded--;
                pending.ownersDone |= ownerIndexBit;
                assertOperationIsConsistent(_operation);
                Confirmation(msg.sender, _operation);
            }
        }
    }

    // Reclaims free slots between valid owners in m_owners.
    
    function reorganizeOwners() private {
        uint free = 1;
        while (free < m_numOwners)
        {
            while (free < m_numOwners && m_owners[free] != 0) free++;
            while (m_numOwners > 1 && m_owners[m_numOwners] == 0) m_numOwners--;
            if (free < m_numOwners && m_owners[m_numOwners] != 0 && m_owners[free] == 0)
            {
                m_owners[free] = m_owners[m_numOwners];
                m_ownerIndex[m_owners[free]] = free;
                m_owners[m_numOwners] = 0;
            }
        }
    }

    function clearPending() private onlyowner {
        uint length = m_multiOwnedPendingIndex.length;
        for (uint i = 0; i < length; ++i) {
            if (m_multiOwnedPendingIndex[i] != 0)
                delete m_multiOwnedPending[m_multiOwnedPendingIndex[i]];
        }
        delete m_multiOwnedPendingIndex;
    }

    function checkOwnerIndex(uint ownerIndex) private pure returns (uint) {
        assert(0 != ownerIndex && ownerIndex <= c_maxOwners);
        return ownerIndex;
    }

    function makeOwnerBitmapBit(address owner) private constant returns (uint) {
        uint ownerIndex = checkOwnerIndex(m_ownerIndex[owner]);
        return 2 ** ownerIndex;
    }

    function isOperationActive(bytes32 _operation) private constant returns (bool) {
        return 0 != m_multiOwnedPending[_operation].yetNeeded;
    }


    function assertOwnersAreConsistent() private constant {
        assert(m_numOwners > 0);
        assert(m_numOwners <= c_maxOwners);
        assert(m_owners[0] == 0);
        assert(0 != m_multiOwnedRequired && m_multiOwnedRequired <= m_numOwners);
    }

    function assertOperationIsConsistent(bytes32 _operation) private constant {
        var pending = m_multiOwnedPending[_operation];
        assert(0 != pending.yetNeeded);
        assert(m_multiOwnedPendingIndex[pending.index] == _operation);
        assert(pending.yetNeeded <= m_multiOwnedRequired);
    }


   	// FIELDS

    uint constant c_maxOwners = 250;

    uint public m_multiOwnedRequired;


    uint public m_numOwners;

    // list of owners (addresses),
    address[256] internal m_owners;

    // index on the list of owners to allow reverse lookup: owner address => index in m_owners
    mapping(address => uint) internal m_ownerIndex;


    // the ongoing operations.
    mapping(bytes32 => MultiOwnedOperationPendingState) internal m_multiOwnedPending;
    bytes32[] internal m_multiOwnedPendingIndex;
}

contract ERC20Basic {
  uint256 public totalSupply;
  function balanceOf(address who) public view returns (uint256);
  function transfer(address to, uint256 value) public returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
}

contract SimpleMultiSigWallet is multiowned {

    event Deposit(address indexed sender, uint value);
    event EtherSent(address indexed to, uint value);

    function SimpleMultiSigWallet(address[] _owners, uint _signaturesRequired)
        public
        multiowned(_owners, _signaturesRequired)
    {
    }

    // @dev Fallback function allows to deposit ether.
    function()
        public
        payable
    {
        if (msg.value > 0)
            Deposit(msg.sender, msg.value);
    }

    // @notice Send `value` of ether to address `to`
    function sendEther(address to, uint value)
        public
        onlymanyowners(keccak256(msg.data))
    {
        require(address(0) != to);
        require(value > 0 && this.balance >= value);
        to.transfer(value);
        EtherSent(to, value);
    }
}

contract MultiSigWalletTest is SimpleMultiSigWallet {

    event TokensSent(address token, address indexed to, uint value);

    modifier notFrozen {
        require(getCurrentTime() >= m_thawTs);
        _;
    }

    function MultiSigWalletTest()
        public
        payable
        SimpleMultiSigWallet(getInitialOwners(), 2)
    {
        m_thawTs = 1546185600;

        
    }

    function getInitialOwners() private pure returns (address[]) {
        address[] memory result = new address[](3);
result[0] = address(0x48693142c1CD9bd9b46d01D23E5f907bbd33D3fb);
result[1] = address(0xedaDA32900884D3766D79B283d286A4C721Ad816);
result[2] = address(0x24c7833Fc55D64c077a0636C6352909572F60f2E);
        return result;
    }

    function sendEther(address to, uint value)
        public
        notFrozen
    {
        super.sendEther(to, value);
    }

    function sendTokens(address token, address to, uint value)
        public
        notFrozen
        onlymanyowners(keccak256(msg.data))
        returns (bool)
    {
        require(address(0) != to);
        require(address(0) != token);
        require(token != to);
        require(isContract(token));

        if (ERC20Basic(token).transfer(to, value)) {
            TokensSent(token, to, value);
            return true;
        }

        return false;
    }


    // PUBLIC VIEW FUNCTIONS

    function tokenBalance(address token) public view returns (uint256) {
        return ERC20Basic(token).balanceOf(this);
    }

    function frozenUntil() public view returns (uint) {
        return m_thawTs;
    }


    // INTERNAL FUNCTIONS

    function isContract(address _addr)
        private
        view
        returns (bool hasCode)
    {
        uint length;
        assembly { length := extcodesize(_addr) }
        return length > 0;
    }

    function getCurrentTime() internal view returns (uint) {
        return now;
    }


    // FIELDS

    uint private m_thawTs;
}
    