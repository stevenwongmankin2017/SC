
pragma solidity ^0.4.20;
/**
 * @title SafeMath
 */
library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }
}


contract ERC721Receiver {
    bytes4 constant ERC721_RECEIVED = 0xf0b9e5ba;

    /**
     * @notice Handle the receipt of an NFT
     */
    function onERC721Received(address _from, uint256 _tokenId, bytes _data) public returns(bytes4);
}


/**
 * @title ERC721 Non-Fungible Token Standard basic interface
 * @dev see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-721.md
 */
contract ERC721Basic {
    event Transfer(address indexed _from, address indexed _to, uint256 _tokenId);
    event Approval(address indexed _owner, address indexed _approved, uint256 _tokenId);
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
    function balanceOf(address _owner) public view returns (uint256 _balance);
    function ownerOf(uint256 _tokenId) public view returns (address _owner);
    function exists(uint256 _tokenId) public view returns (bool _exists);
    function approve(address _to, uint256 _tokenId) public;
    function getApproved(uint256 _tokenId) public view returns (address _operator);
    function setApprovalForAll(address _operator, bool _approved) public;
    function isApprovedForAll(address _owner, address _operator)
    public view returns (bool);
    function transferFrom(address _from, address _to, uint256 _tokenId) public;
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public;
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes _data) public;
}


/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 */
contract ERC721Enumerable is ERC721Basic {
    function totalSupply() public view returns (uint256);
    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint256 _tokenId);
    function tokenByIndex(uint256 _index) public view returns (uint256);
}


/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 */
contract ERC721Metadata is ERC721Basic {
    function name() public view returns (string _name);
    function symbol() public view returns (string _symbol);
    function tokenURI(uint256 _tokenId) public view returns (string);
}


/**
 * @title ERC-721 Non-Fungible Token Standard, full implementation interface
 */
contract ERC721 is ERC721Basic, ERC721Enumerable, ERC721Metadata {}


/**
 * @title ERC721 Non-Fungible Token Standard basic implementation
 */
contract ERC721BasicToken is ERC721Basic {
    using SafeMath for uint256;
    using AddressUtils for address;
    bytes4 constant ERC721_RECEIVED = 0xf0b9e5ba;

    // Mapping from token ID to owner
    mapping (uint256 => address) internal tokenOwner;

    // Mapping from token ID to approved address
    mapping (uint256 => address) internal tokenApprovals;

    // Mapping from owner to number of owned token
    mapping (address => uint256) internal ownedTokensCount;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) internal operatorApprovals;

    modifier onlyOwnerOf(uint256 _tokenId) {
        require(ownerOf(_tokenId) == msg.sender);
        _;
    }

    modifier canTransfer(uint256 _tokenId) {
        require(isApprovedOrOwner(msg.sender, _tokenId));
        _;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        require(_owner != address(0));
        return ownedTokensCount[_owner];
    }

    function ownerOf(uint256 _tokenId) public view returns (address) {
        address owner = tokenOwner[_tokenId];
        require(owner != address(0));
        return owner;
    }

    function exists(uint256 _tokenId) public view returns (bool) {
        address owner = tokenOwner[_tokenId];
        return owner != address(0);
    }

    function approve(address _to, uint256 _tokenId) public {
        address owner = ownerOf(_tokenId);
        require(_to != owner);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender));

        if (getApproved(_tokenId) != address(0) || _to != address(0)) {
            tokenApprovals[_tokenId] = _to;
            Approval(owner, _to, _tokenId);
        }
    }

    function getApproved(uint256 _tokenId) public view returns (address) {
        return tokenApprovals[_tokenId];
    }

    function setApprovalForAll(address _to, bool _approved) public {
        require(_to != msg.sender);
        operatorApprovals[msg.sender][_to] = _approved;
        ApprovalForAll(msg.sender, _to, _approved);
    }

    function isApprovedForAll(address _owner, address _operator) public view returns (bool)
    {
        return operatorApprovals[_owner][_operator];
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public canTransfer(_tokenId)
    {
        require(_from != address(0));
        require(_to != address(0));

        clearApproval(_from, _tokenId);
        removeTokenFrom(_from, _tokenId);
        addTokenTo(_to, _tokenId);

        Transfer(_from, _to, _tokenId);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public canTransfer(_tokenId)
    {
        // solium-disable-next-line arg-overflow
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes _data) public canTransfer(_tokenId)
    {
        transferFrom(_from, _to, _tokenId);
        // solium-disable-next-line arg-overflow
        require(checkAndCallSafeTransfer(_from, _to, _tokenId, _data));
    }

    function isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool)
    {
        address owner = ownerOf(_tokenId);
        // Disable solium check because of
        // https://github.com/duaraghav8/Solium/issues/175
        // solium-disable-next-line operator-whitespace
        return (
        _spender == owner ||
        getApproved(_tokenId) == _spender ||
        isApprovedForAll(owner, _spender)
        );
    }

    function _mint(address _to, uint256 _tokenId) internal {
        require(_to != address(0));
        addTokenTo(_to, _tokenId);
        Transfer(address(0), _to, _tokenId);
    }

    function _burn(address _owner, uint256 _tokenId) internal {
        clearApproval(_owner, _tokenId);
        removeTokenFrom(_owner, _tokenId);
        Transfer(_owner, address(0), _tokenId);
    }

    function clearApproval(address _owner, uint256 _tokenId) internal {
        require(ownerOf(_tokenId) == _owner);
        if (tokenApprovals[_tokenId] != address(0)) {
            tokenApprovals[_tokenId] = address(0);
            Approval(_owner, address(0), _tokenId);
        }
    }

    function addTokenTo(address _to, uint256 _tokenId) internal {
        require(tokenOwner[_tokenId] == address(0));
        tokenOwner[_tokenId] = _to;
        ownedTokensCount[_to] = ownedTokensCount[_to].add(1);
    }

    function removeTokenFrom(address _from, uint256 _tokenId) internal {
        require(ownerOf(_tokenId) == _from);
        ownedTokensCount[_from] = ownedTokensCount[_from].sub(1);
        tokenOwner[_tokenId] = address(0);
    }

    function checkAndCallSafeTransfer(address _from, address _to, uint256 _tokenId, bytes _data) internal returns (bool)
    {
        if (!_to.isContract()) {
            return true;
        }
        bytes4 retval = ERC721Receiver(_to).onERC721Received(
        _from, _tokenId, _data);
        return (retval == ERC721_RECEIVED);
    }
}

/**
 * @title Ownable
 */

 contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function Ownable() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


library AddressUtils {

    
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

}

/**
 * @title Full ERC721 Token
 */
contract ERC721Token is ERC721, ERC721BasicToken {
    // Token name
    string internal name_;

    // Token symbol
    string internal symbol_;

    // Mapping from owner to list of owned token IDs
    mapping(address => uint256[]) internal ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) internal ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] internal allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) internal allTokensIndex;

    // Optional mapping for token URIs
    mapping(uint256 => string) internal tokenURIs;

    /**
     * @dev Constructor function
     */
    function ERC721Token(string _name, string _symbol) public {
        name_ = _name;
        symbol_ = _symbol;
    }

    function name() public view returns (string) {
        return name_;
    }

    function symbol() public view returns (string) {
        return symbol_;
    }

    function tokenURI(uint256 _tokenId) public view returns (string) {
        require(exists(_tokenId));
        return tokenURIs[_tokenId];
    }

    function tokenOfOwnerByIndex(address _owner, uint256 _index) public view returns (uint256)
    {
        require(_index < balanceOf(_owner));
        return ownedTokens[_owner][_index];
    }
    
    function tokensOfOwner(address _owner) public view returns (uint256[])
    {
        return ownedTokens[_owner];
    }

    function totalSupply() public view returns (uint256) {
        return allTokens.length;
    }

    function tokenByIndex(uint256 _index) public view returns (uint256) {
        require(_index < totalSupply());
        return allTokens[_index];
    }

    function _setTokenURI(uint256 _tokenId, string _uri) internal {
        require(exists(_tokenId));
        tokenURIs[_tokenId] = _uri;
    }

    function addTokenTo(address _to, uint256 _tokenId) internal {
        super.addTokenTo(_to, _tokenId);
        uint256 length = ownedTokens[_to].length;
        ownedTokens[_to].push(_tokenId);
        ownedTokensIndex[_tokenId] = length;
    }

    function removeTokenFrom(address _from, uint256 _tokenId) internal {
        super.removeTokenFrom(_from, _tokenId);

        uint256 tokenIndex = ownedTokensIndex[_tokenId];
        uint256 lastTokenIndex = ownedTokens[_from].length.sub(1);
        uint256 lastToken = ownedTokens[_from][lastTokenIndex];

        ownedTokens[_from][tokenIndex] = lastToken;
        ownedTokens[_from][lastTokenIndex] = 0;

        ownedTokens[_from].length--;
        ownedTokensIndex[_tokenId] = 0;
        ownedTokensIndex[lastToken] = tokenIndex;
    }

    function _mint(address _to, uint256 _tokenId) internal {
        super._mint(_to, _tokenId);

        allTokensIndex[_tokenId] = allTokens.length;
        allTokens.push(_tokenId);
    }
    
	function _burn(address _owner, uint256 _tokenId) internal {
        super._burn(_owner, _tokenId);

        if (bytes(tokenURIs[_tokenId]).length != 0) {
            delete tokenURIs[_tokenId];
        }

        uint256 tokenIndex = allTokensIndex[_tokenId];
        uint256 lastTokenIndex = allTokens.length.sub(1);
        uint256 lastToken = allTokens[lastTokenIndex];

        allTokens[tokenIndex] = lastToken;
        allTokens[lastTokenIndex] = 0;

        allTokens.length--;
        allTokensIndex[_tokenId] = 0;
        allTokensIndex[lastToken] = tokenIndex;
    }
}


/**
 * @title Burnable Token
 */
contract BurnableToken is ERC721BasicToken {
    function burn(uint256 _tokenId) public {
        _burn(msg.sender, _tokenId);
    }
}


contract MintableToken is ERC721Token, Ownable {
    event MintFinished();

    bool public mintingFinished = false;

    modifier canMint() {
        require(!mintingFinished);
        _;
    }
    
    function mint(address _to, uint256 _tokenId) public onlyOwner canMint {
        _mint(_to, _tokenId);
    }
    
    /**
     * @dev Function to stop minting new tokens.
     */
    function finishMinting() onlyOwner canMint public returns (bool) {
        mintingFinished = true;
        MintFinished();
        return true;
    }    
}

/**
 * @title Capped token
 * @dev Mintable token with a token cap.
 */
contract CappedToken is MintableToken {
    uint256 public cap;

    function CappedToken(uint256 _cap) public {
        require(_cap > 0);
        cap = _cap;
    }

    /**
     * @dev Function to mint tokens
     */
    function mint(address _to, uint256 _tokenId) onlyOwner canMint public {
        require(totalSupply().add(1) <= cap);

        return super.mint(_to, _tokenId);
    }

}

/**
 * @title Pausable
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused);
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() onlyOwner whenNotPaused public {
        paused = true;
        Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() onlyOwner whenPaused public {
        paused = false;
        Unpause();
    }
}

/**
 * @title Pausable token
 **/
contract PausableToken is ERC721BasicToken, Pausable {
    function approve(address _to, uint256 _tokenId) public whenNotPaused {
        return super.approve(_to, _tokenId);
    }

    function setApprovalForAll(address _to, bool _approved) public whenNotPaused {
        return super.setApprovalForAll(_to, _approved);
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public whenNotPaused canTransfer(_tokenId) {
        return super.transferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public whenNotPaused canTransfer(_tokenId) {
        return super.safeTransferFrom(_from, _to, _tokenId);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes _data) public whenNotPaused canTransfer(_tokenId) {
        return super.safeTransferFrom(_from, _to, _tokenId, _data);
    }
}


/**
 * @title PausableBurnable token
 **/
contract BurnablePausableToken is PausableToken, BurnableToken {
    function burn(uint256 _tokenId) public whenNotPaused {
        super.burn(_tokenId);
    }
}

/**
 * @title ERC721TestToken
 **/


contract ERC721TestToken is ERC721Token , CappedToken, BurnablePausableToken {
    function ERC721TestToken()
        public
        payable
        ERC721Token('testgame', 'TESTGAME')
        CappedToken(10000) 
    { 
        
        
    }

    function setTokenURI(uint256 _tokenId, string _uri) external onlyOwnerOf(_tokenId) {
        super._setTokenURI(_tokenId, _uri);
    }
}

    