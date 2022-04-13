// SPDX-License-Identifier: MIT
pragma solidity ^8.0.0;

import "@openZeppelin/contracts/utils/address.sol";
import "@openZeppelin/contracts/interfaces/IERC20.sol";
import "@openZeppelin/contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openZeppelin/contracts/interfaces/IERC165.sol";
import "@openZeppelin/contracts/mocks/ERC165.sol";
import "@openZeppelin/contracts/interfaces/IERC1155.sol";
import "@openZeppelin/contracts/interfaces/IERC721.sol";
import "./interfaces/IbondTreasury.sol";
import "@openZeppelin/contracts/access/Ownable.sol";

/// @title   Bonding Contract
/// @author  JeffX, AbominableSasquatch, Jomari
/// @notice  Bonding ERC1155s and ERC721s in return for GDT tokens
contract BondingContract is Ownable {
    using SafeERC20 for IERC20;
    
    /// EVENTS ///

    /// @notice Emitted when A bond is created
    /// @param deposit Address of where bond is deposited to
    /// @param payout Amount of GDT to be paid out
    /// @param expires Block number bond will be fully redeemable
    event BondCreated( uint deposit, uint payout, uint expires );

    /// @notice Emitted when a bond is redeemed
    /// @param recipient Address receiving GDT
    /// @param payout Amount of GDT redeemed
    /// @param remaining Amount of GDT left to be paid out
    event BondRedeemed( address recipient, uint payout, uint remaining );

    
    /// STATE VARIABLES ///
    
    /// @notice Guild DAO Token
    IERC20 immutable public GDT;
    /// @notice Parallel ERC1155
    IERC1155 immutable public LL;
    /// @notice Custom Treasury
    IGuildBondingTreasury immutable public customTreasury;

    //Need to cut out Guild DAO

    /// @notice Guild DAO address
    address immutable public guildDAO;
    /// @notice Guild treasury address
    address public guildTreasury;

    /// @notice Total Parallel tokens that have been bonded
    uint public totalPrincipalBonded;
    /// @notice Total GDT tokens given as payout
    uint public totalPayoutGiven;
    /// @notice Vesting term in blocks
    uint public vestingTerm;


    /// @notice Percent fee that goes to Guild
    uint public immutable guildFee = 33300;

    /// @notice Array of IDs that have been bondable
    uint[] public bondedIds;

    /// @notice Bool if bond contract has been initialized
    bool public initialized;

    /// @notice Stores bond information for depositors
    mapping( address => Bond ) public bondInfo;

    /// @notice Stores bond information for a Parallel ID
    mapping( uint => IdDetails ) public idDetails;

    
    /// STRUCTS ///

    /// @notice           Details of an addresses current bond
    /// @param payout     GDT tokens remaining to be paid
    /// @param vesting    Blocks left to vest
    /// @param lastBlock  Last interaction
    struct Bond {
        uint payout;
        uint vesting;
        uint lastBlock;
    }

    //may need a new parameter for different contracts

    /// @notice                   Details of an ID that is to be bonded
    /// @param bondPrice          Payout price of the ID
    /// @param remainingToBeSold  Remaining amount of tokens that can be bonded
    /// @param inArray            Bool if ID is in array that keeps track of IDs
    struct IdDetails {
        uint bondPrice;
        uint remainingToBeSold;
        bool inArray;
    }

    
    /// CONSTRUCTOR ///

    /// @param _customTreasury   Address of custom treasury
    /// @param _LL               Address of the NFT token
    /// @param _guildTreasury  Address of the Guild treasury
    /// @param _initialOwner     Address of the initial owner
    /// @param _guildDAO       Address of Guild DAO
    constructor(
        address _customTreasury, 
        address _LL, 
        address _guildTreasury,
        address _initialOwner, 
        address _guildDAO
    ) {
        require( _customTreasury != address(0) );
        customTreasury = IGuildBondingTreasury( _customTreasury );
        GDT = IERC20( IGuildBondingTreasury(_customTreasury).GDT() );
        require( _LL != address(0) );
        LL = IERC1155( _LL );
        require( _guildTreasury != address(0) );
        guildTreasury = _guildTreasury;
        require( _initialOwner != address(0) );
        policy = _initialOwner;
        require( _guildDAO != address(0) );
        guildDAO = _guildDAO;
    }


    /// POLICY FUNCTIONS ///

    /// @notice              Initializes bond and sets vesting rate
    /// @param _vestingTerm  Vesting term in blocks
    function initializeBond(uint _vestingTerm) external onlyPolicy() {
        require(!initialized, "Already initialized");
        vestingTerm = _vestingTerm;
        initialized = true;
    }

    /// @notice          Updates current vesting term
    /// @param _vesting  New vesting in blocks
    function setVesting( uint _vesting ) external onlyPolicy() {
        require(initialized, "Not initalized");
        vestingTerm = _vesting;
    }

    /// @notice           Set bond price and how many to be sold for each ID
    /// @param _ids       Array of IDs that will be sold
    /// @param _prices    GDT given to bond correspond ID in `_ids`
    /// @param _toBeSold  Number of IDs looking to be acquired
    function setIdDetails(uint[] calldata _ids, uint[] calldata _prices, uint _toBeSold) external onlyPolicy() {
        require(_ids.length == _prices.length, "Lengths do not match");
        for(uint i; i < _ids.length; i++) {
            IdDetails memory idDetail = idDetails[_ids[i]];
            idDetail.bondPrice = _prices[i];
            idDetail.remainingToBeSold = _toBeSold;
            if(!idDetail.inArray) {
                bondedIds.push(_ids[i]);
                idDetail.inArray = true;
            }
            idDetails[_ids[i]] = idDetail;

        }
    }

    /// @notice                  Updates address to send Guild fee to
    /// @param _guildTreasury  Address of new Guild treasury
    function changeGuildTreasury(address _guildTreasury) external {
        require( msg.sender == guildDAO, "Only Guild DAO" );
        guildTreasury = _guildTreasury;
    }

    /// USER FUNCTIONS ///
    
    /// @notice            Bond Parallel ERC1155 to get GDT tokens
    /// @param _id         ID number that is being bonded
    /// @param _amount     Amount of sepcific `_id` to bond
    /// @param _depositor  Address that GDT tokens will be redeemable for
    function deposit(uint _id, uint _amount, address _depositor) external returns (uint) {
        require(initialized, "Not initalized");
        require( idDetails[_id].bondPrice > 0 && idDetails[_id].remainingToBeSold >= _amount, "Not bondable");
        require( _amount > 0, "Cannot bond 0" );
        require( _depositor != address(0), "Invalid address" );

        uint payout;
        uint fee;

        (payout, fee) = payoutFor( _id ); // payout and fee is computed

        payout = payout.mul(_amount);
        fee = fee.mul(_amount);
                
        // depositor info is stored
        bondInfo[ _depositor ] = Bond({ 
            payout: bondInfo[ _depositor ].payout.add( payout ),
            vesting: vestingTerm,
            lastBlock: block.number
        });

        idDetails[_id].remainingToBeSold = idDetails[_id].remainingToBeSold.sub(_amount);

        totalPrincipalBonded = totalPrincipalBonded.add(_amount); // total bonded increased
        totalPayoutGiven = totalPayoutGiven.add(payout); // total payout increased

        customTreasury.sendGDT( payout.add(fee) );

        GDT.safeTransfer(guildTreasury, fee);

        LL.safeTransferFrom( msg.sender, address(customTreasury), _id, _amount, "" ); // transfer principal bonded to custom treasury

        // indexed events are emitted
        emit BondCreated( _id, payout, block.number.add( vestingTerm ) );

        return payout; 
    }
    
    /// @notice            Redeem bond for `depositor`
    /// @param _depositor  Address of depositor being redeemed
    /// @return            Amount of GDT redeemed
    function redeem(address _depositor) external returns (uint) {
        Bond memory info = bondInfo[ _depositor ];
        uint percentVested = percentVestedFor( _depositor ); // (blocks since last interaction / vesting term remaining)

        if ( percentVested >= 10000 ) { // if fully vested
            delete bondInfo[ _depositor ]; // delete user info
            emit BondRedeemed( _depositor, info.payout, 0 ); // emit bond data
            GDT.safeTransfer( _depositor, info.payout );
            return info.payout;

        } else { // if unfinished
            // calculate payout vested
            uint payout = info.payout.mul( percentVested ).div( 10000 );

            // store updated deposit info
            bondInfo[ _depositor ] = Bond({
                payout: info.payout.sub( payout ),
                vesting: info.vesting.sub( block.number.sub( info.lastBlock ) ),
                lastBlock: block.number
            });

            emit BondRedeemed( _depositor, payout, bondInfo[ _depositor ].payout );
            GDT.safeTransfer( _depositor, payout );
            return payout;
        }
        
    }

    /// VIEW FUNCTIONS ///
    
    /// @notice          Payout and fee for a specific bond ID
    /// @param _id       ID to get payout and fee for
    /// @return payout_  Amount of GDT user will recieve for bonding `_id`
    /// @return fee_     Amount of GDT Guild will recieve for the bonding of `_id`
    function payoutFor( uint _id ) public view returns ( uint payout_, uint fee_) {
        uint price = idDetails[_id].bondPrice;
        fee_ = price.mul( guildFee ).div( 1e6 );
        payout_ = price.sub(fee_);
    }

    /// @notice                 Calculate how far into vesting `_depositor` is
    /// @param _depositor       Address of depositor
    /// @return percentVested_  Percent `_depositor` is into vesting
    function percentVestedFor( address _depositor ) public view returns ( uint percentVested_ ) {
        Bond memory bond = bondInfo[ _depositor ];
        uint blocksSinceLast = block.number.sub( bond.lastBlock );
        uint vesting = bond.vesting;

        if ( vesting > 0 ) {
            percentVested_ = blocksSinceLast.mul( 10000 ).div( vesting );
        } else {
            percentVested_ = 0;
        }
    }

    /// @notice                 Calculate amount of payout token available for claim by `_depositor`
    /// @param _depositor       Address of depositor
    /// @return pendingPayout_  Pending payout for `_depositor`
    function pendingPayoutFor( address _depositor ) external view returns ( uint pendingPayout_ ) {
        uint percentVested = percentVestedFor( _depositor );
        uint payout = bondInfo[ _depositor ].payout;

        if ( percentVested >= 10000 ) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mul( percentVested ).div( 10000 );
        }
    }

    /// @notice  Returns all the ids that are bondable and the amounts that can be bonded for each
    /// @return  Array of all IDs that are bondable
    /// @return  Array of amount remaining to be bonded for each bondable ID
    function bondableIds() external view returns (uint[] memory, uint[] memory) {
        uint numberOfBondable;

        for(uint i = 0; i < bondedIds.length; i++) {
            uint id = bondedIds[i];
            (bool active,) = canBeBonded(id);
            if(active) numberOfBondable++;
        }

        uint256[] memory ids = new uint256[](numberOfBondable);
        uint256[] memory leftToBond = new uint256[](numberOfBondable);

        uint nonce;
        for(uint i = 0; i < bondedIds.length; i++) {
            uint id = bondedIds[i];
            (bool active, uint amount) = canBeBonded(id);
            if(active) {
                ids[nonce] = id;
                leftToBond[nonce] = amount;
                nonce++;
            }
        }

        return (ids, leftToBond);
    }

    /// @notice     Determines if `_id` can be bonded, and if so how much is left
    /// @param _id  ID to check if can be bonded
    /// @return     Bool if `_id` can be bonded
    /// @return     Amount of tokens that be bonded for `_id`
    function canBeBonded(uint _id) public view returns (bool, uint) {
        IdDetails memory idDetail = idDetails[_id];
        if(idDetail.bondPrice > 0 && idDetail.remainingToBeSold > 0) {
            return (true, idDetail.remainingToBeSold);
        } else {
            return (false, 0);
        }
    }

    
}
