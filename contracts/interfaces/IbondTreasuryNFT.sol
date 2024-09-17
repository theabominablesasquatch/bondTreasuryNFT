pragma solidity 0.7.5;

interface IbondTreasuryNFT {
    function sendGDT(uint _amountPayoutToken) external;
    function valueOfToken( address _principalToken, uint _amount ) external view returns ( uint value_ );
    function GDT() external view returns (address);
}