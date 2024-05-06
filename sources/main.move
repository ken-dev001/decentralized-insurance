module insurance::insurance {
    // Imports
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};

    // Errors
    const ENotEnough: u64 = 0;
    const EClaimPending: u64 = 1;
    const EUndeclaredClaim: u64 = 2;
    const ENotValidatedByInsurer: u64 = 3;
    const ENotValidatedByAuthority: u64 = 4;
    const ENotPolicyHolder: u64 = 5;

    // Struct definitions
    struct AdminCap has key { id:UID }
    struct InsurerCap has key { id:UID }
    struct AuthorityCap has key { id:UID }

    struct InsuranceClaim has key, store {
        id: UID,                            // Claim object ID
        policy_holder_address: address,     // Policy holder address
        insurer_claim_id: u64,              // Insurer Claim ID
        authority_claim_id: u64,            // Authority claim ID
        amount: u64,                        // Claim amount
        payout: Balance<SUI>,               // SUI Balance
        insurer_is_pending: bool,           // True if the insurer has paid the policy holder
        insurer_validation: bool,           // True if the insurer has validated the claim
        authority_validation: bool          // True if the authority has confirmed the existence of the claim
    }

    struct InsurancePolicy has key, store {
        id: UID,                            // Policy ID
        policy_holder_address: address,     // Policy holder address
        policy_amount: u64,                 // Policy amount
        is_active: bool                     // True if the policy is active
    }

    // Module initializer
    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }

    // Accessors
    public entry fun insurer_claim_id(_: &InsurerCap, insurance_claim: &InsuranceClaim): u64 {
        insurance_claim.insurer_claim_id
    }

    public entry fun amount(insurance_claim: &InsuranceClaim, ctx: &mut TxContext): u64 {
        assert!(insurance_claim.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        insurance_claim.amount
    }

    public entry fun claim_id(_: &AuthorityCap, insurance_claim: &InsuranceClaim): u64 {
        insurance_claim.authority_claim_id
    }

    public entry fun is_paid(insurance_claim: &InsuranceClaim): u64 {
        balance::value(&insurance_claim.payout)
    }

    public entry fun insurer_has_validated(insurance_claim: &InsuranceClaim): bool {
        insurance_claim.insurer_validation
    }

    public entry fun authority_has_validated(insurance_claim: &InsuranceClaim): bool {
        insurance_claim.authority_validation
    }

    public entry fun policy_amount(insurance_policy: &InsurancePolicy, ctx: &mut TxContext): u64 {
        assert!(insurance_policy.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        insurance_policy.policy_amount
    }

    public entry fun is_policy_active(insurance_policy: &InsurancePolicy): bool {
        insurance_policy.is_active
    }

    // Public - Entry functions
    public entry fun create_insurance_claim(cl_id: u64, auth_id:u64, amount: u64, ctx: &mut TxContext) {
        transfer::share_object(InsuranceClaim {
            policy_holder_address: tx_context::sender(ctx),
            id: object::new(ctx),
            insurer_claim_id: cl_id,
            authority_claim_id: auth_id,
            amount: amount,
            payout: balance::zero(),
            insurer_is_pending: false,
            insurer_validation: false,
            authority_validation: false
        });
    }

    public entry fun create_insurer_cap(_: &AdminCap, insurer_address: address, ctx: &mut TxContext) {
        transfer::transfer(InsurerCap { 
            id: object::new(ctx),
        }, insurer_address);
    }

    public entry fun create_authority_cap(_: &AdminCap, authority_address: address, ctx: &mut TxContext) {
        transfer::transfer(AuthorityCap { 
            id: object::new(ctx),
        }, authority_address);
    }

    public entry fun create_insurance_policy(policy_amount: u64, ctx: &mut TxContext) {
        transfer::share_object(InsurancePolicy {
            policy_holder_address: tx_context::sender(ctx),
            id: object::new(ctx),
            policy_amount: policy_amount,
            is_active: true
        });
    }

    public entry fun deactivate_insurance_policy(insurance_policy: &mut InsurancePolicy, ctx: &mut TxContext) {
        assert!(insurance_policy.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        insurance_policy.is_active = false;
    }

    public entry fun activate_insurance_policy(insurance_policy: &mut InsurancePolicy, ctx: &mut TxContext) {
        assert!(insurance_policy.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        insurance_policy.is_active = true;
    }

    public entry fun edit_claim_id(insurance_claim: &mut InsuranceClaim, claim_id: u64, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.insurer_is_pending, EClaimPending);
        insurance_claim.authority_claim_id = claim_id;
    }

    public entry fun payout(insurance_claim: &mut InsuranceClaim, funds: &mut Coin<SUI>) {
        assert!(coin::value(funds) >= insurance_claim.amount, ENotEnough);
        assert!(insurance_claim.authority_claim_id == 0, EUndeclaredClaim);

        let coin_balance = coin::balance_mut(funds);
        let paid = balance::split(coin_balance, insurance_claim.amount);

        balance::join(&mut insurance_claim.payout, paid);
    }

    public entry fun validate_with_insurer(_: &InsurerCap, insurance_claim: &mut InsuranceClaim) {
        insurance_claim.insurer_validation = true;
    }

    public entry fun validate_by_authority(_: &AuthorityCap, insurance_claim: &mut InsuranceClaim) {
        insurance_claim.authority_validation = true;
    }

    public entry fun claim_from_insurer(insurance_claim: &mut InsuranceClaim, insurer_address: address, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.authority_claim_id == 0, EUndeclaredClaim);

        // Transfer the balance
        let amount = balance::value(&insurance_claim.payout);
        let payout = coin::take(&mut insurance_claim.payout, amount, ctx);
        transfer::public_transfer(payout, tx_context::sender(ctx));

        // Transfer the ownership
        insurance_claim.policy_holder_address = insurer_address;
    }

    public entry fun claim_from_authority(insurance_claim: &mut InsuranceClaim, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address != tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.insurer_is_pending, EClaimPending);
        assert!(insurance_claim.insurer_validation == false, ENotValidatedByInsurer);
        assert!(insurance_claim.authority_validation == false, ENotValidatedByAuthority);

        // Transfer the balance
        let amount = balance::value(&insurance_claim.payout);
        let payout = coin::take(&mut insurance_claim.payout, amount, ctx);
        transfer::public_transfer(payout, tx_context::sender(ctx));
    }
}