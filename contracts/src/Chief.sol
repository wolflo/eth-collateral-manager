pragma solidity 0.5.2;

import "./Vault.sol";
import "../lib/Interesting.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

// TODO 1/9
// diagram out the flow between contracts -> esp. storage between chief and vault
// Get the tester contract working (i.e. external contract for testing Chief)
// Look into 0x proxy plans
// Call dad
// ** add callTime and some way to track timeout / collateral status
    // - need some sort of state to prevent abuse of move() while waiting for zen
    // - update interest before entering zen, then era + zen = liquidation time

// TODO: dss uses 0.5.0, need to see how they do interest then switch to ^0.5

// TODO: need a max zen?
    // bad things from a super high zen:
    //  - could overflow endZen time in move(), but that would really
    //  only stop the contract from moving money, which would be the case
    //  anyway if their zen time overflows a uint256
    //  - ?

// CCM - contract-collateral-manager
// Ownable for setting oracle stuff - hopefully governance in the future
contract Chief is Ownable, Interesting, ReentrancyGuard {
    // TODO:
    enum State{zen, foo, bar}

    // Note: 0x standard followed in favor of our own naming convention here
    struct Order {
        address makerAddress;           // Address that created the order.
        address takerAddress;           // Address that is allowed to fill the order. If set to 0, any address is allowed to fill the order.
        address feeRecipientAddress;    // Address that will recieve fees when order is filled.
        address senderAddress;          // Address that is allowed to call Exchange contract methods that affect this order. If set to 0, any address is allowed to call these methods.
        uint256 makerAssetAmount;       // Amount of makerAsset being offered by maker. Must be greater than 0.
        uint256 takerAssetAmount;       // Amount of takerAsset being bid on by maker. Must be greater than 0.
        uint256 makerFee;               // Amount of ZRX paid to feeRecipient by maker when order is filled. If set to 0, no transfer of ZRX from maker to feeRecipient will be attempted.
        uint256 takerFee;               // Amount of ZRX paid to feeRecipient by taker when order is filled. If set to 0, no transfer of ZRX from taker to feeRecipient will be attempted.
        uint256 expirationTimeSeconds;  // Timestamp in seconds at which order expires.
        uint256 salt;                   // Arbitrary number to facilitate uniqueness of the order's hash.
        bytes makerAssetData;           // ABIv2 encoded data that can be decoded by a specified proxy contract when transferring makerAsset.
        bytes takerAssetData;           // ABIv2 encoded data that can be decoded by a specified proxy contract when transferring takerAsset.
    }
    struct TPair {
        // TODO: oracle stuff
        bool use;
    }
    struct Asset {
        bool use;
        uint tax;
        uint mat;   // Minimum Collateralization Ratio
        uint axe;   // liquidation penalty
    }
    struct Mama {
        address due;
        mapping (address => Asset) gems;
    }
    struct Acct {
        // Set by managing contract
        uint    tab;    // Max payout amt 
        uint    bal;    // due balance, denominated in due tokens
        uint    zen;    // time given to return collateral to due before liquidation 
        bool    mom;    // true ? use local gems : use mamas[who]. ** make sure mamas[mom].axe valid (> 1)?
        address who;    // Address of managing contract, man, 
        address due;    // Address of the ERC20 token to pay out in
        mapping (address => Asset) gems;    // Tokens that can be held as collateral and the parameters

        // Set by user
        bool    opt;    // opt-in to dutch auction? auc
        uint    val;    // gem balance, denominated in gems?
        address gem;    // Token currently held (can be in addition to due balance)
        Order   jet;    // Default order to take if called for payment.
        mapping (address => bool) pals; // Approved to handle trader's account

        uint    era;    // Time of last interest accrual
    }

    // uint min_tab;        // tab below which it's not profitable for keepers to bite?
    uint public max_tax;    // maximum interest rate
    uint public max_tab;    // tab above which keepers can bite TODO: change name of this if tab is not updated with interest
    uint public acct_id;    // Incremented for keepers to find accounts
    
    mapping (address => Mama) public mamas; // Contract-wide Asset Paramaters
    // Only internal bc of compiler complaint about nested structs. Need to create getter
    mapping (bytes32 => Acct) internal accts; // keccak256(contract, user) => Account
    mapping (uint => bytes32) public radar; // acct_id => accts key for the acct, finds? finda
    mapping (address => mapping(address => TPair)) public pairs;  // due => gem => Trading Pair

    address public proxy;   // Only used for automatic getter
    Vault public vault;

    constructor(address _vault, address _proxy) public {
        vault = Vault(_vault);
        proxy = _proxy;
    }

    // called by the managing contract
    // if _mom == true, _due should be 0
    function _open(
        uint    _tab,   // Collateral amount, denominated in _due token
        uint    _zen,
        address _lad,   // Address of the payer TODO: can't be msg.sender?
        address _due,   // Address of the token to pay out in
        bool    _mom    // If true, use contract-wide Asset Params. else, set below
    ) private returns (bool) {
        // Account user can't be zero
        require(_lad != address(0), "ccm-chief-open-lad-invalid");
        
        // Payout token can't be 0 unless mama params being used. 
        // NOTE: No checks on whether _due has any token matches
        // if _mom, check contract-wide due address, else check _due
        if (_mom) {
            require(mamas[msg.sender].due != address(0), "ccm-chief-open-mama-due-invalid");
        } else {
            require(_due != address(0), "ccm-chief-open-due-invalid");
        }

        // Check that owed amt under limit
        require(_tab > 0 && _tab < max_tab, "ccm-chief-open-tab-invalid");
        // Grab the account
        bytes32 key = keccak256(abi.encodePacked(msg.sender, _lad));
        Acct storage acct = accts[key];
        // Check that account doesn't exist already. TODO: check who too?
        require(acct.era == 0, "ccm-chief-open-account-exists");
        // Add id to radar and increment acct_id
        radar[acct_id] = key;
        acct_id = add(acct_id, 1); 
        // Initialize the account
        acct.who = msg.sender;
        acct.tab = _tab;
        acct.mom = _mom;
        acct.zen = _zen;
        acct.era = now;
        if (!_mom) {acct.due = _due;}    // TODO: just set this anyway?

        require(vault.take(_due, _lad, _tab));
        // TODO
        acct.bal = _tab;

        return true;       
    }

    // add new Asset to mama or acct
    function _ngem(
        uint    _tax,   // interest rate charged on swapped collateral   
        uint    _mat,   // minimum collateralization ratio, as a ray
        uint    _axe,   // liquidation penalty, as a ray
        address _gem,   // address of the token to add
        address _lad,   // address of the holder / payer
        bool    _mom    // set this to contract-wide params?
    ) private returns (bool) {
        // do all the checks
        // if mom grab from mom else grab from baby
        // do last check and set

        // TODO: make sure we don't need a minimum for axe
        // liquidation penalty > 1 required to prevent auction grinding
        require(_axe > RAY, "ccm-chief-ngem-axe-invalid");
        // extra collateral has to be able to at least cover axe
        require(_mat > _axe, "ccm-chief-ngem-mat-invalid");
        // Check that tax is valid
        require(_tax < max_tax, "ccm-chief-ngem-tax-invalid");

        // TODO: probably don't need these, checking pairs
        // require(mama.due != address(0), "collateral-vault-mama-due-not-set");
        // require(_gem != address(0), "collateral-vault-mama-address-invalid");

        bytes32 key;
        address _due;
        Asset memory ngem;
        // mama or account?
        if (_mom) { 
            _due = mamas[msg.sender].due;
            ngem = mamas[msg.sender].gems[_gem]; 
        } else {
             // Check that account exists 
            key = keccak256(abi.encodePacked(msg.sender, _lad));
            require(accts[key].era > 0, "ccm-chief-ngem-acct-nonexistant");
            // Check that account is not using the mom params (waste of gas and
            // deceptive to the contract to set params that aren't used)
            require(!accts[key].mom, "ccm-chief-ngem-acct-uses-mom");
            _due = accts[key].due;
            ngem = accts[key].gems[_gem];
        }

        // gem must be an approved token pair with due
        require(pairs[_due][_gem].use, "ccm-chief-ngem-token-pair-invalid");

        // TODO: mama.mat>0 very important, prevents editing gem params
        // after setting use to false. Make sure there's no way around this
        // Also, does just checking mat work?
        // require(!mama.use && mama.mat > 0, "collateral-vault-mama-gem-in-use");
        require(ngem.mat > 0, "ccm-chief-ngem-gem-in-use");

        ngem.use = true;
        ngem.tax = _tax;
        ngem.mat = _mat;
        ngem.axe = _axe;

        if(_mom) {mamas[msg.sender].gems[_gem] = ngem;}
        else {accts[key].gems[_gem] = ngem;}

        return true; 
    }

    // State altering functions
    ////// Managing Contract Functions:
    // open()       - implemented
    // mdue()   - add initial due to mamas, born, girl?, mama
    //    - add initial due to specific acct, -- Not needed, can't be initialized w/o one
    // mama()   - add an Asset to mamas, mgem, 
    // baby()   - add an Asset to specific acct, daut, bgem
    //          - disable a gem in mama for future users - could also use mama/daut(false) to remove, mpop, clean, moff and boff, m_on and b_on
    //          - disable a gem for specific acct as long as not currently held, bump, bpop  ** make these be able to toggle use
    // move()   - pay out to specified address, send-probs confusing, post, drop, give, move, take
    // close()?  - set tab = 0, either leave user balance or transfer it to pull() balances
    //
    ////// User Functions:
    // lock()   - add either gem or due tokens, as long as it stays safe
    // free()   - claim either gem or due tokens, as long as it stays safe
    //          - set, change, or remove jet, zoom, tend, plane, edit, lift, land
    // meet()   - approve/unapprove a pal, talk, 
    //          - opt in/out of dutch auction, care, tend, 
    // swap()   - use 0x order to trade due or gem for new gem, as long as it stays safe. Also, delete jet
    // pull()   - calls Vault.give(), pays out users         
    //
    ////// Keeper Functions:
    // acct_id()      - implemented
    // bite()
    //
    ////// Vault Functions:
    // take() - transfers tokens from user to vault
    // give() - transfers tokens from vault to user
    // gift() - updates a user's pull balance
    //
    ////// Proxy Functions:
    // deal()   - transfers tokens
    //
    ////// Auction Functions:
    //
    ////// Intermediate Functions:
    // safe()


    /////////////
    // External Functions
    ////////////

    // Set the contract-wide due token
    function mdue(address _due) external returns (bool) {
        // _due can't be zero
        require(_due != address(0), "ccm-chief-mdue-token-invalid");
        // can't change due token
        require(mamas[msg.sender].due == address(0), "ccm-chief-mdue-already-set");
        // set due
        mamas[msg.sender].due = _due;
    } 

    // Claim your payout
    function pull(address _gem, uint amt) external returns (bool) {
        return vault.give(_gem, msg.sender, amt);
    }

    // add an Asset to mamas
    function mama(
        uint    _tax,   // interest rate charged on tab - .....   
        uint    _mat,   // minimum collateralization ratio, as a ray
        uint    _axe,   // liquidation penalty, as a ray
        address _gem    // address of the token to add
    ) external returns (bool) {
        return _ngem(_tax, _mat, _axe, _gem, address(0), true);        
    }
    // Add an Asset to a specific account
    function baby(
        uint    _tax,   // interest rate charged on swapped collateral   
        uint    _mat,   // minimum collateralization ratio, as a ray
        uint    _axe,   // liquidation penalty, as a ray
        address _gem,   // address of the token to add
        address _lad    // address of the holder / payer
    ) external returns (bool) {
        return _ngem(_tax, _mat, _axe, _gem, _lad, false);
    }
    // Open an account
    function open(
        uint    _tab,   // Collateral amount, denominated in _due token
        uint    _zen,
        address _lad,   // Address of the payer TODO: can't be msg.sender?
        address _due,   // Address of the token to pay out in
        bool    _mom    // If true, use contract-wide Asset Params. else, set below
    ) external nonReentrant returns (bool) {
        return _open(_tab, _zen, _lad, _due, _mom);
    }
    // Open an account that will use mama params
    function open(uint _tab, uint _zen, address _lad) external nonReentrant returns (bool) {
        return _open(_tab, _zen, _lad, address(0), false);
    }

    
    /////////////
    // Getters
    /////////////
    


}