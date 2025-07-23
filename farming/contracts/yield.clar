;; Yield Farming Protocol Contract
;; Implements yield farming and token staking mechanics with custom minimum function

;; Define fungible token trait
(define-trait fungible-token-trait
    (
        (transfer (uint principal principal) (response bool uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-decimals () (response uint uint))
        (get-balance (principal) (response uint uint))
        (get-total-supply () (response uint uint))
    )
)

;; Define token contracts
(define-constant primary-token-contract .primary-token)
(define-constant secondary-token-contract .secondary-token)

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1))
(define-constant ERR-INSUFFICIENT-RESERVES (err u2))
(define-constant ERR-EXISTING-POSITION (err u3))
(define-constant ERR-NO-ACTIVE-POSITION (err u4))
(define-constant ERR-BELOW-MINIMUM-THRESHOLD (err u5))
(define-constant ERR-STILL-LOCKED (err u6))
(define-constant ERR-INVALID-TOKEN-PAIR (err u7))
(define-constant ERR-COMPUTATION-FAILED (err u8))
(define-constant ERR-INVALID-ADDRESS (err u9))
(define-constant ERR-OWNERSHIP-VALIDATION-FAILED (err u10))

;; Constants
(define-constant MIN_DEPOSIT_AMOUNT u100000) ;; Minimum deposit requirement
(define-constant LOCKUP_DURATION u144) ;; ~24 hours in blocks
(define-constant BASE_YIELD_RATE u100) ;; 1.00x base multiplier
(define-constant PROTOCOL_FEE_RATE u30) ;; 0.3% fee
(define-constant NULL_ADDRESS 'SP000000000000000000002Q6VF78)

;; Data variables
(define-data-var protocol-admin principal tx-sender)
(define-data-var total-value-locked uint u0)
(define-data-var last-update-height uint u0)
(define-data-var protocol-status bool true)
(define-data-var current-yield-rate uint BASE_YIELD_RATE)

;; Data maps for yield farmers
(define-map yield-positions
    principal
    {
        primary-amount: uint,
        secondary-amount: uint,
        share-tokens: uint,
        entry-block: uint,
        last-harvest: uint,
        unlock-block: uint
    }
)

;; Vault data structure
(define-map farming-vaults
    uint
    {
        primary-reserves: uint,
        secondary-reserves: uint,
        outstanding-shares: uint,
        accumulated-fees: uint
    }
)

;; Custom minimum function implementation
(define-private (find-minimum (value-x uint) (value-y uint))
    (if (<= value-x value-y)
        value-x
        value-y))

;; Read-only functions
(define-read-only (get-farmer-position (farmer principal))
    (map-get? yield-positions farmer)
)

(define-read-only (get-vault-details (vault-id uint))
    (map-get? farming-vaults vault-id)
)

(define-read-only (compute-share-allocation (primary-deposit uint) (secondary-deposit uint))
    (let (
        (vault (unwrap! (get-vault-details u1) (err ERR-COMPUTATION-FAILED)))
        (existing-shares (get outstanding-shares vault))
    )
    (ok (if (is-eq existing-shares u0)
        (sqrti (* primary-deposit secondary-deposit))
        (find-minimum
            (/ (* primary-deposit existing-shares) (get primary-reserves vault))
            (/ (* secondary-deposit existing-shares) (get secondary-reserves vault))
        )))
    )
)

;; Public functions
(define-public (deposit-tokens (primary-token <fungible-token-trait>) (secondary-token <fungible-token-trait>) (primary-amount uint) (secondary-amount uint))
    (begin
        (asserts! (and 
            (is-eq (contract-of primary-token) primary-token-contract)
            (is-eq (contract-of secondary-token) secondary-token-contract))
            ERR-INVALID-TOKEN-PAIR)
            
        (let (
            (farmer-position (default-to 
                {
                    primary-amount: u0,
                    secondary-amount: u0,
                    share-tokens: u0,
                    entry-block: u0,
                    last-harvest: block-height,
                    unlock-block: u0
                }
                (map-get? yield-positions tx-sender)))
            (share-calculation (compute-share-allocation primary-amount secondary-amount))
        )
        (asserts! (>= primary-amount MIN_DEPOSIT_AMOUNT) ERR-BELOW-MINIMUM-THRESHOLD)
        (asserts! (>= secondary-amount MIN_DEPOSIT_AMOUNT) ERR-BELOW-MINIMUM-THRESHOLD)
        (asserts! (is-eq (get share-tokens farmer-position) u0) ERR-EXISTING-POSITION)
        
        (let 
            ((allocated-shares (unwrap! share-calculation ERR-COMPUTATION-FAILED)))
            
            ;; Transfer tokens to contract
            (try! (contract-call? primary-token transfer primary-amount tx-sender (as-contract tx-sender)))
            (try! (contract-call? secondary-token transfer secondary-amount tx-sender (as-contract tx-sender)))
            
            ;; Update farmer position
            (map-set yield-positions tx-sender
                {
                    primary-amount: primary-amount,
                    secondary-amount: secondary-amount,
                    share-tokens: allocated-shares,
                    entry-block: block-height,
                    last-harvest: block-height,
                    unlock-block: (+ block-height LOCKUP_DURATION)
                }
            )
            
            ;; Update vault reserves
            (try! (update-vault-reserves primary-amount secondary-amount allocated-shares))
            (ok allocated-shares)))
    )
)

(define-public (withdraw-tokens (primary-token <fungible-token-trait>) (secondary-token <fungible-token-trait>))
    (begin
        (asserts! (and 
            (is-eq (contract-of primary-token) primary-token-contract)
            (is-eq (contract-of secondary-token) secondary-token-contract))
            ERR-INVALID-TOKEN-PAIR)
            
        (let (
            (farmer-position (unwrap! (get-farmer-position tx-sender) ERR-NO-ACTIVE-POSITION))
            (current-height block-height)
        )
        (asserts! (>= current-height (get unlock-block farmer-position)) ERR-STILL-LOCKED)
        
        (let (
            (primary-withdrawal (get primary-amount farmer-position))
            (secondary-withdrawal (get secondary-amount farmer-position))
            (position-shares (get share-tokens farmer-position))
        )
            ;; Calculate yield rewards
            (let (
                (earned-rewards (compute-yield-rewards tx-sender))
                (total-primary (+ primary-withdrawal earned-rewards))
                (total-secondary (+ secondary-withdrawal earned-rewards))
            )
                ;; Transfer tokens back to farmer
                (try! (as-contract (contract-call? primary-token transfer total-primary (as-contract tx-sender) tx-sender)))
                (try! (as-contract (contract-call? secondary-token transfer total-secondary (as-contract tx-sender) tx-sender)))
                
                ;; Update state
                (map-delete yield-positions tx-sender)
                (try! (update-vault-reserves total-primary total-secondary position-shares))
                (ok true)
            ))))
)

;; Private helper functions
(define-private (update-vault-reserves (primary-delta uint) (secondary-delta uint) (share-delta uint))
    (let (
        (vault (unwrap! (get-vault-details u1) ERR-COMPUTATION-FAILED))
        (updated-primary-reserves (- (get primary-reserves vault) primary-delta))
        (updated-secondary-reserves (- (get secondary-reserves vault) secondary-delta))
        (updated-shares (- (get outstanding-shares vault) share-delta))
    )
    (asserts! (and (>= updated-primary-reserves u0) (>= updated-secondary-reserves u0) (>= updated-shares u0)) ERR-INSUFFICIENT-RESERVES)
    (map-set farming-vaults u1
        {
            primary-reserves: updated-primary-reserves,
            secondary-reserves: updated-secondary-reserves,
            outstanding-shares: updated-shares,
            accumulated-fees: (get accumulated-fees vault)
        }
    )
    (ok true))
)

(define-private (compute-yield-rewards (farmer principal))
    (let (
        (farmer-position (unwrap! (get-farmer-position farmer) u0))
        (staking-duration (- block-height (get last-harvest farmer-position)))
        (position-share (get share-tokens farmer-position))
    )
    (/ (* (* position-share staking-duration) (var-get current-yield-rate)) u10000))
)

;; Administrative functions
(define-private (verify-and-update-admin (new-admin principal))
    (begin
        (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR-INVALID-ADDRESS)
        (let ((admin-position (get-farmer-position new-admin)))
            (asserts! (is-some admin-position) ERR-INVALID-ADDRESS)
            (let ((position-data (unwrap! admin-position ERR-OWNERSHIP-VALIDATION-FAILED)))
                (asserts! (> (get share-tokens position-data) u0) ERR-OWNERSHIP-VALIDATION-FAILED)
                (asserts! (>= block-height (get unlock-block position-data)) ERR-OWNERSHIP-VALIDATION-FAILED)
                (ok (var-set protocol-admin new-admin)))))
)

(define-public (transfer-admin-rights (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (not (is-eq new-admin NULL_ADDRESS)) ERR-INVALID-ADDRESS)
        (try! (verify-and-update-admin new-admin))
        (ok true))
)

(define-public (adjust-yield-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> new-rate u0) ERR-INVALID-TOKEN-PAIR)
        (ok (var-set current-yield-rate new-rate)))
)

(define-public (toggle-protocol-status)
    (begin
        (asserts! (is-eq tx-sender (var-get protocol-admin)) ERR-UNAUTHORIZED-ACCESS)
        (var-set protocol-status (not (var-get protocol-status)))
        (ok true))
)