// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract bondingTreasuryNFT is Ownable, ERC1155Holder, ERC721Holder{
   using SafeERC20 for IERC20;

 /// EVENTS ///

    /// @notice Emitted when a contract is whitelisted
    /// @param bondContract Address of contract whitelisted
    event BondContractWhitelisted(address bondContract);

    /// @notice Emitted when a bond dewhitelisted
    /// @param bondContract Address of contract dewhitelisted
    event BondContractDewhitelisted(address bondContract);

    /// @notice Emitted ERC20 tokens are withdrawn
    /// @param token Address of token being withdrawn
    /// @param destination Address of where withdrawn token is sent
    /// @param amount Amount of tokens withdrawn
    event WithdrawERC20(address token, address destination, uint amount);

    /// @notice Emitted when ERC1155 tokens are withdrawn
    /// @param token Address of token being withdrawn
    /// @param destination Address of where withdrawn token is sent
    /// @param ids Array of ids that are being witdrawn
    /// @param amounts Amounts of token being withdrawn corresponding with ID
    event WithdrawERC1155(address token, address destination, uint[] ids, uint[] amounts);

    //May need to update variables
    /// @notice Emitted when ERC721 tokens are withdrawn
    /// @param token Address of token being withdrawn
    /// @param destination Address of where withdrawn token is sent
    /// @param id id that will be witdrawn
    event WithdrawERC721(address token, address destination,uint id);
    
    
    /// STATE VARIABLES ///
    
    //need to name the token distributed
    /// @notice Guild DAO Token
    address public immutable GDT;

    //Initial owner info
    address public policy;

    /// @notice Stores approved bond contracts
    mapping(address => bool) public bondContract; 

    
    /// CONSTRUCTOR ///

    /// @param _GDT           Address of GDT
    /// @param _initialOwner  Address of the initial owner
    constructor(address _GDT, address _initialOwner) {
        require( _GDT != address(0) );
        GDT = _GDT;
        require( _initialOwner != address(0) );
        policy = _initialOwner;
    }


    /// BOND CONTRACT FUNCTION ///

    /// @notice                    Sends bond contract GDT
    /// @param _amountPayoutToken  Amount of GDT to be sent
    function sendGDT(uint _amountPayoutToken) external {
        require(bondContract[msg.sender], "msg.sender is not a bond contract");
        IERC20(GDT).safeTransfer(msg.sender, _amountPayoutToken);
    }

    /// VIEW FUNCTION ///

    /// @notice                 Returns payout token valuation of principal
    /// @param _principalToken  Address of principal token
    /// @param _amount          Amount of `_principalToken` to value
    /// @return value_          Value of `_amount` of `_principalToken`
    function valueOfToken( address _principalToken, uint _amount ) public view returns ( uint value_ ) {
        // convert amount to match payout token decimals
        value_ = _amount * ( 10 ** IERC20( GDT ).decimals() ) / ( 10 ** IERC20( _principalToken ).decimals() );
    }


    /// POLICY FUNCTIONS ///

    /// @notice              Withdraw ERC20 token to `_destination`
    /// @param _token        Address of token to withdraw
    /// @param _destination  Address of where to send `_token`
    /// @param _amount       Amount of `_token` to withdraw
    function withdrawERC20(address _token, address _destination, uint _amount) external onlyOwner() {
        IERC20(_token).safeTransfer(_destination, _amount);
        emit WithdrawERC20(_token, _destination, _amount);
    }

    /// @notice              Withdraw ERC1155 token to `_destination`
    /// @param _token        Address of token to withdraw
    /// @param _destination  Address of where to send `_token`
    /// @param _ids          Array of IDs of `_token`
    /// @param _amounts      Array of amount of corresponding `_id`
    function withdrawERC1155(address _token, address _destination, uint[] calldata _ids, uint[] calldata _amounts) external onlyOwner() {
        IERC1155(_token).safeBatchTransferFrom(address(this), _destination, _ids, _amounts, '');
        emit WithdrawERC1155(_token, _destination, _ids, _amounts);
    }

    //Revisit this function - not batched

    /// @notice              Withdraw ERC721 token to `_destination`
    /// @param _token        Address of token to withdraw
    /// @param _destination  Address of where to send `_token`
    /// @param _id          IDs of `_token`
    function withdrawERC721(address _token, address _destination, uint _id) external onlyOwner() {
        IERC721(_token).safeTransferFrom(address(this), _destination, _id);
        emit WithdrawERC721(_token, _destination, _id);
    }


    /// @notice               Whitelist bond contract
    /// @param _bondContract  Address to whitelist
    function whitelistBondContract(address _bondContract) external onlyOwner() {
        bondContract[_bondContract] = true;
        emit BondContractWhitelisted(_bondContract);
    }

    /// @notice               Dewhitelist bond contract
    /// @param _bondContract  Address to dewhitelist
    function dewhitelistBondContract(address _bondContract) external onlyOwner() {
        bondContract[_bondContract] = false;
        emit BondContractDewhitelisted(_bondContract);
    }
}



