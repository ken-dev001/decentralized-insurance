/// Module for insurance-related operations
module insurance::insurance {
    // Imports
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};

    /// Error struct for better error handling
    struct Error has drop, store {
        error_code: u64,
        error_message: vector<u8>,
    }

    /// Error codes
    const E_NOT_ENOUGH: u64 = 0;
    const E_CLAIM_PENDING: u64 = 1;
    const E_UNDECLARED_CLAIM: u64 = 2;
    const E_NOT_VALIDATED_BY_INSURER: u64 = 3;
    const E_NOT_VALIDATED_BY_AUTHORITY: u64 = 4;
    const E_NOT_POLICY_HOLDER: u64 = 5;

    /// Struct definitions
    struct AdminCap has key { id: UID }
    struct InsurerCap has key { id: UID }
    struct AuthorityCap has key { id: UID }

    struct InsuranceClaim has key, store {
        id: UID,                            // Claim object ID
        policy_holder_address: address,     // Policy holder address
        insurer_claim_id: u64,              // Insurer Claim ID
        authority_claim_id: u64,            // Authority claim ID
        amount: u64,                        // Claim amount
        payout: Balance<SUI>,               // SUI Balance
        insurer_is_pending: bool,           // True if the insurer has paid the policy holder
        insurer_validation: bool,           // True if the insurer has validated the claim
        authority_validation: bool,         // True if the authority has confirmed the existence of the claim
    }

    struct InsurancePolicy has key, store {
        id: UID,                            // Policy ID
        policy_holder_address: address,     // Policy holder address
        policy_amount: u64,                 // Policy amount
        is_active: bool,                    // True if the policy is active
        expiration_date: u64,               // Policy expiration date (Unix timestamp)
    }

    /// Module initializer
    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx))
    }

    /// Accessors
    public fun insurer_claim_id(_: &InsurerCap, insurance_claim: &InsuranceClaim): u64 {
        insurance_claim.insurer_claim_id
    }

    public fun amount(insurance_claim: &InsuranceClaim, ctx: &mut TxContext): u64 {
        assert!(insurance_claim.policy_holder_address != tx_context::sender(ctx), E_NOT_POLICY_HOLDER);
        insurance_claim.amount
    }

    public fun claim_id(_: &AuthorityCap, insurance_claim: &InsuranceClaim): u64 {
        insurance_claim.authority_claim_id
    }

    public fun is_paid(insurance_claim: &InsuranceClaim): u64 {
        balance::value(&insurance_claim.payout)
    }

    public fun insurer_has_validated(insurance_claim: &InsuranceClaim): bool {
        insurance_claim.insurer_validation
    }

    public fun authority_has_validated(insurance_claim: &InsuranceClaim): bool {
        insurance_claim.authority_validation
    }

    public fun policy_amount(insurance_policy: &InsurancePolicy, ctx: &mut TxContext): u64 {
        assert!(insurance_policy.policy_holder_address != tx_context::sender(ctx), E_NOT_POLICY_HOLDER);
        insurance_policy.policy_amount
    }

    public fun is_policy_active(insurance_policy: &InsurancePolicy): bool {
        insurance_policy.is_active
    }

    public fun policy_expiration_date(insurance_policy: &InsurancePolicy): u64 {
        insurance_policy.expiration_date
    }

    /// Public - Entry functions
    public entry fun create_insurance_claim(
        cl_id: u64,
        auth_id: u64,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        // Input validation
        assert!(amount > 0, Error { error_code: E_NOT_ENOUGH, error_message: b"Claim amount must be greater than zero" });

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
        });
    }

    public entry fun create_insurer_cap(
        _: &AdminCap,
        insurer_address: address,
        ctx: &mut TxContext,
    ) {
        transfer::transfer(
            InsurerCap {
                id: object::new(ctx),
            },
            insurer_address,
        );
    }

    public entry fun create_authority_cap(
        _: &AdminCap,
        authority_address: address,
        ctx: &mut TxContext,
    ) {
        transfer::transfer(
            AuthorityCap {
                id: object::new(ctx),
            },
            authority_address,
        );
    }

    public entry fun create_insurance_policy(
        policy_amount: u64,
        expiration_date: u64,
        ctx: &mut TxContext,
    ) {
        // Input validation
        assert!(policy_amount > 0, Error { error_code: E_NOT_ENOUGH, error_message: b"Policy amount must be greater than zero" });
        assert!(expiration_date > tx_context::epoch(ctx), Error { error_code: E_NOT_ENOUGH, error_message: b"Expiration date must be in the future" });

        transfer::share_object(InsurancePolicy {
            policy_holder_address: tx_context::sender(ctx),
            id: object::new(ctx),
            policy_amount: policy_amount,
            is_active: true,
            expiration_date: expiration_date,
        });
    }

    public entry fun deactivate_insurance_policy(
        insurance_policy: &mut InsurancePolicy,
        ctx: &mut TxContext,
    ) {
        assert!(insurance_policy.policy_holder_address != tx_context::sender(ctx), E_NOT_POLICY_HOLDER);
        insurance_policy.is_active = false;
    }

    public entry fun activate_insurance_policy(
        insurance_policy: &mut InsurancePolicy,
        ctx: &mut TxContext,
    ) {
        assert!(insurance_policy.policy_holder_address != tx_context::sender(ctx), E_NOT_POLICY_HOLDER);
        insurance_policy.is_active = true;
    }

    public entry fun edit_claim_id(
        insurance_claim: &mut InsuranceClaim,
        claim_id: u64,
        ctx: &mut TxContext,
    ) {
        assert!(insurance_claim.policy_holder_address != tx_context::sender(ctx), E_NOT_POLICY_HOLDER);
        assert!(insurance_claim.insurer_is_pending, E_CLAIM_PENDING);
        insurance_claim.authority_claim_id = claim_id;
    }

    public entry fun payout(
        insurance_claim: &mut InsuranceClaim,
        funds: &mut Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        assert!(coin::value(funds) >= insurance_claim.amount, Error { error_code: E_NOT_ENOUGH, error_message: b"Insufficient funds for payout" });
        assert!(insurance_claim.authority_claim_id == 0, Error { error_code: E_UNDECLARED_CLAIM, error_message: b"Claim ID not set by the authority" });
        assert!(!insurance_claim.insurer_is_pending, Error { error_code: E_CLAIM_PENDING, error_message: b"Claim payout already initiated" });

        // Split the required amount from the provided funds
        let coin_balance = coin::balance_mut(funds);
        let paid = balance::split(coin_balance, insurance_claim.amount);

        // Join the split amount to the insurance claim's payout balance
        balance::join(&mut insurance_claim.payout, paid);

        // Mark the insurer as pending
        insurance_claim.insurer_is_pending = true;
    }
}