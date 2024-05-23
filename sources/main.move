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
    const EInvalidCap: u64 = 6;
    const EClaimAlreadyProcessed: u64 = 7;
    const EClaimNotPending: u64 = 8;
    // Struct definitions
    struct AdminCap has key { id: UID }
    struct InsurerCap has key { id: UID }
    struct AuthorityCap has key { id: UID }
    struct InsuranceClaim has key, store {
        id: UID,
        policy_holder_address: address,
        insurer_claim_id: u64,
        authority_claim_id: u64,
        amount: u64,
        payout: Balance<SUI>,
        insurer_is_pending: bool,
        insurer_validation: bool,
        authority_validation: bool,
        is_active: bool,
    }
    struct InsurancePolicy has key, store {
        id: UID,
        policy_holder_address: address,
        policy_amount: u64,
        is_active: bool,
    }
    // Module initializer
    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx));
    }
    // Accessors
    public fun get_insurer_claim_id(insurer_cap: &InsurerCap, insurance_claim: &InsuranceClaim): u64 {
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        insurance_claim.insurer_claim_id
    }
    public fun get_claim_amount(insurance_claim: &InsuranceClaim, ctx: &mut TxContext): u64 {
        assert!(insurance_claim.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        insurance_claim.amount
    }
    public fun get_authority_claim_id(authority_cap: &AuthorityCap, insurance_claim: &InsuranceClaim): u64 {
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        insurance_claim.authority_claim_id
    }
    public fun get_payout_amount(insurance_claim: &InsuranceClaim): u64 {
        balance::value(&insurance_claim.payout)
    }
    public fun is_insurer_validated(insurance_claim: &InsuranceClaim): bool {
        insurance_claim.insurer_validation
    }
    public fun is_authority_validated(insurance_claim: &InsuranceClaim): bool {
        insurance_claim.authority_validation
    }
    public fun get_policy_amount(insurance_policy: &InsurancePolicy, ctx: &mut TxContext): u64 {
        assert!(insurance_policy.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        insurance_policy.policy_amount
    }
    public fun is_policy_active(insurance_policy: &InsurancePolicy): bool {
        insurance_policy.is_active
    }
    // Public - Entry functions
    public entry fun create_insurance_claim(cl_id: u64, auth_id: u64, amount: u64, ctx: &mut TxContext) {
        transfer::share_object(InsuranceClaim {
            policy_holder_address: tx_context::sender(ctx),
            id: object::new(ctx),
            insurer_claim_id: cl_id,
            authority_claim_id: auth_id,
            amount: amount,
            payout: balance::zero(),
            insurer_is_pending: false,
            insurer_validation: false,
            authority_validation: false,
            is_active: true,
        });
    }
    public entry fun create_insurer_cap(admin_cap: &AdminCap, insurer_address: address, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == admin_cap.id, EInvalidCap);
        transfer::transfer(InsurerCap {
            id: object::new(ctx),
        }, insurer_address);
    }
    public entry fun create_authority_cap(admin_cap: &AdminCap, authority_address: address, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == admin_cap.id, EInvalidCap);
        transfer::transfer(AuthorityCap {
            id: object::new(ctx),
        }, authority_address);
    }
    public entry fun create_insurance_policy(policy_amount: u64, ctx: &mut TxContext) {
        transfer::share_object(InsurancePolicy {
            policy_holder_address: tx_context::sender(ctx),
            id: object::new(ctx),
            policy_amount: policy_amount,
            is_active: true,
        });
    }
    public entry fun deactivate_insurance_policy(insurance_policy: &mut InsurancePolicy, ctx: &mut TxContext) {
        assert!(insurance_policy.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        insurance_policy.is_active = false;
    }
    public entry fun activate_insurance_policy(insurance_policy: &mut InsurancePolicy, ctx: &mut TxContext) {
        assert!(insurance_policy.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        insurance_policy.is_active = true;
    }
    public entry fun edit_claim_id(insurance_claim: &mut InsuranceClaim, claim_id: u64, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        insurance_claim.authority_claim_id = claim_id;
    }
    public entry fun payout(insurance_claim: &mut InsuranceClaim, funds: &mut Coin<SUI>, ctx: &mut TxContext) {
        assert!(coin::value(funds) >= insurance_claim.amount, ENotEnough);
        assert!(insurance_claim.authority_claim_id != 0, EUndeclaredClaim);
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        let coin_balance = coin::balance_mut(funds);
        let paid = balance::split(coin_balance, insurance_claim.amount);
        balance::join(&mut insurance_claim.payout, paid);
    }
    public entry fun validate_with_insurer(insurer_cap: &InsurerCap, insurance_claim: &mut InsuranceClaim) {
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        insurance_claim.insurer_validation = true;
    }
    public entry fun validate_by_authority(authority_cap: &AuthorityCap, insurance_claim: &mut InsuranceClaim) {
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        insurance_claim.authority_validation = true;
    }
    public entry fun claim_from_insurer(insurance_claim: &mut InsuranceClaim, insurer_address: address, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.authority_claim_id != 0, EUndeclaredClaim);
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        let amount = balance::value(&insurance_claim.payout);
        let payout = coin::take(&mut insurance_claim.payout, amount, ctx);
        transfer::public_transfer(payout, tx_context::sender(ctx));
        insurance_claim.policy_holder_address = insurer_address;
        insurance_claim.is_active = false;
    }
    public entry fun claim_from_authority(insurance_claim: &mut InsuranceClaim, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        assert!(insurance_claim.insurer_is_pending, EClaimPending);
        assert!(insurance_claim.insurer_validation, ENotValidatedByInsurer);
        assert!(insurance_claim.authority_validation, ENotValidatedByAuthority);
        assert!(insurance_claim.is_active, EClaimAlreadyProcessed);
        let amount = balance::value(&insurance_claim.payout);
        let payout = coin::take(&mut insurance_claim.payout, amount, ctx);
        transfer::public_transfer(payout, tx_context::sender(ctx));
        insurance_claim.is_active = false;
    }
    // Revoke a claim
    public entry fun revoke_claim(insurance_claim: &mut InsuranceClaim, ctx: &mut TxContext) {
        assert!(insurance_claim.policy_holder_address == tx_context::sender(ctx), ENotPolicyHolder);
        assert!(!insurance_claim.is_active, EClaimNotPending);
        insurance_claim.is_active = false;
    }
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx)
    }
}