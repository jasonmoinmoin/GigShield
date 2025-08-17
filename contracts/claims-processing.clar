;; GigShield Claims Processing Contract
;; Clarity v2 (compatible with Stacks 2.1+, latest syntax as of 2025)
;; Handles claim submissions, automated validation, payouts, and disputes for gig worker insurance.
;; Integrates with Insurance Pool for payouts, Oracle for verification, and Governance DAO for disputes.
;; Sophisticated features: Claim lifecycle management, evidence hashing, timeout mechanisms, multi-admin support, event logging.

(define-trait insurance-pool-trait
  (
    (distribute-payout (principal uint) (response bool uint))
    (get-pool-balance () (response uint uint))
  )
)

(define-trait oracle-trait
  (
    (verify-claim-data (uint (buff 256)) (response bool uint))
  )
)

(define-trait governance-dao-trait
  (
    (escalate-dispute (uint principal (buff 512)) (response uint uint))
  )
)

(define-constant ERR-NOT-AUTHORIZED u200)
(define-constant ERR-INVALID-CLAIM u201)
(define-constant ERR-CLAIM-ALREADY-PROCESSED u202)
(define-constant ERR-INSUFFICIENT-POOL-BALANCE u203)
(define-constant ERR-ORACLE-VERIFICATION-FAILED u204)
(define-constant ERR-PAUSED u205)
(define-constant ERR-INVALID-AMOUNT u206)
(define-constant ERR-CLAIM-TIMEOUT u207)
(define-constant ERR-NO-EVIDENCE u208)
(define-constant ERR-INVALID-STATE u209)
(define-constant ERR-ZERO-ADDRESS u210)
(define-constant ERR-INVALID-DESCRIPTION u211)

(define-constant CLAIM-STATE-PENDING u0)
(define-constant CLAIM-STATE-VERIFIED u1)
(define-constant CLAIM-STATE-PAID u2)
(define-constant CLAIM-STATE-DISPUTED u3)
(define-constant CLAIM-STATE-REJECTED u4)

(define-constant CLAIM-TIMEOUT-BLOCKS u144) ;; ~1 day in Stacks blocks
(define-constant MAX-DESCRIPTION-LEN u256)
(define-constant MIN-DESCRIPTION-LEN u10)

;; Contract state
(define-data-var admin principal tx-sender)
(define-data-var paused bool false)
(define-data-var pool-contract principal 'SP000000000000000000002Q6VF78)
(define-data-var oracle-contract principal 'SP000000000000000000002Q6VF78)
(define-data-var dao-contract principal 'SP000000000000000000002Q6VF78)
(define-data-var claim-counter uint u0)
(define-data-var multi-admins (list 10 principal) (list tx-sender))

;; Claim data structure
(define-map claims uint
  {
    claimant: principal,
    amount: uint,
    evidence-hash: (buff 32), ;; SHA256 hash of evidence
    description: (buff 256),
    submit-block: uint,
    state: uint,
    verifier: (optional principal)
  }
)

;; Claim history for auditing
(define-map claim-history uint (list 10 {action: (string-ascii 32), block: uint, actor: principal}))

;; Events (using print for logging in Clarity)
(define-private (log-event (claim-id uint) (action (string-ascii 32)))
  (print {event: "claim-action", id: claim-id, action: action, actor: tx-sender, block: block-height})
)

;; Private: is-admin or multi-admin
(define-private (is-authorized)
  (or (is-eq tx-sender (var-get admin))
      (is-some (index-of (var-get multi-admins) tx-sender)))
)

;; Private: ensure not paused
(define-private (ensure-not-paused)
  (asserts! (not (var-get paused)) (err ERR-PAUSED))
)

;; Private: validate claim existence and state
(define-private (validate-claim-state (claim-id uint) (expected-state uint))
  (match (map-get? claims claim-id)
    claim (asserts! (is-eq (get state claim) expected-state) (err ERR-INVALID-STATE))
    (err ERR-INVALID-CLAIM)
  )
)

;; Private: validate description
(define-private (validate-description (desc (buff 256)))
  (begin
    (asserts! (>= (len desc) MIN-DESCRIPTION-LEN) (err ERR-INVALID-DESCRIPTION))
    (asserts! (<= (len desc) MAX-DESCRIPTION-LEN) (err ERR-INVALID-DESCRIPTION))
    (ok true)
  )
)

;; Set contract addresses (pool, oracle, dao)
(define-public (set-pool-contract (new-pool principal))
  (begin
    (asserts! (is-authorized) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-pool 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (var-set pool-contract new-pool)
    (ok true)
  )
)

(define-public (set-oracle-contract (new-oracle principal))
  (begin
    (asserts! (is-authorized) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-oracle 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (var-set oracle-contract new-oracle)
    (ok true)
  )
)

(define-public (set-dao-contract (new-dao principal))
  (begin
    (asserts! (is-authorized) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-dao 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (var-set dao-contract new-dao)
    (ok true)
  )
)

;; Add/remove multi-admin
(define-public (add-multi-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-some (index-of (var-get multi-admins) new-admin))) (err ERR-NOT-AUTHORIZED))
    (var-set multi-admins (unwrap! (as-max-len? (append (var-get multi-admins) new-admin) u10) (err ERR-NOT-AUTHORIZED)))
    (ok true)
  )
)

(define-public (remove-multi-admin (target principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (var-set multi-admins (filter not-equal-target (var-get multi-admins)))
    (ok true)
  )
)

;; Private helper for filter
(define-private (not-equal-target (p principal))
  (not (is-eq p (var-get admin)))
)

;; Pause/unpause
(define-public (set-paused (pause bool))
  (begin
    (asserts! (is-authorized) (err ERR-NOT-AUTHORIZED))
    (var-set paused pause)
    (ok pause)
  )
)

;; Submit a claim
(define-public (submit-claim (amount uint) (evidence-hash (buff 32)) (description (buff 256)))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (> (len evidence-hash) u0) (err ERR-NO-EVIDENCE))
    (try! (validate-description description))
    (let ((claim-id (+ (var-get claim-counter) u1)))
      (map-set claims claim-id
        {
          claimant: tx-sender,
          amount: amount,
          evidence-hash: evidence-hash,
          description: description,
          submit-block: block-height,
          state: CLAIM-STATE-PENDING,
          verifier: none
        }
      )
      (map-set claim-history claim-id (list {action: "submitted", block: block-height, actor: tx-sender}))
      (var-set claim-counter claim-id)
      (log-event claim-id "submitted")
      (ok claim-id)
    )
  )
)

;; Verify claim (called by authorized or oracle callback simulation)
(define-public (verify-claim (claim-id uint) (evidence-data (buff 256)))
  (begin
    (ensure-not-paused)
    (asserts! (> claim-id u0) (err ERR-INVALID-CLAIM))
    (validate-claim-state claim-id CLAIM-STATE-PENDING)
    (let ((claim (unwrap! (map-get? claims claim-id) (err ERR-INVALID-CLAIM)))
          (oracle (as-contract (contract-call? (var-get oracle-contract) verify-claim-data claim-id evidence-data))))
      (asserts! (is-ok oracle) (err ERR-ORACLE-VERIFICATION-FAILED))
      (asserts! (unwrap! oracle (err ERR-ORACLE-VERIFICATION-FAILED)) (err ERR-ORACLE-VERIFICATION-FAILED))
      (map-set claims claim-id (merge claim {state: CLAIM-STATE-VERIFIED, verifier: (some tx-sender)}))
      (map-insert claim-history claim-id (unwrap! (as-max-len? (append (unwrap! (map-get? claim-history claim-id) (err ERR-INVALID-CLAIM)) {action: "verified", block: block-height, actor: tx-sender}) u10) (err ERR-INVALID-CLAIM)))
      (log-event claim-id "verified")
      (ok true)
    )
  )
)

;; Process payout for verified claim
(define-public (process-payout (claim-id uint))
  (begin
    (ensure-not-paused)
    (asserts! (> claim-id u0) (err ERR-INVALID-CLAIM))
    (validate-claim-state claim-id CLAIM-STATE-VERIFIED)
    (let ((claim (unwrap! (map-get? claims claim-id) (err ERR-INVALID-CLAIM)))
          (pool-balance (unwrap! (contract-call? (var-get pool-contract) get-pool-balance) (err ERR-INSUFFICIENT-POOL-BALANCE)))
          (payout-amount (get amount claim)))
      (asserts! (>= pool-balance payout-amount) (err ERR-INSUFFICIENT-POOL-BALANCE))
      (try! (as-contract (contract-call? (var-get pool-contract) distribute-payout (get claimant claim) payout-amount)))
      (map-set claims claim-id (merge claim {state: CLAIM-STATE-PAID}))
      (map-insert claim-history claim-id (unwrap! (as-max-len? (append (unwrap! (map-get? claim-history claim-id) (err ERR-INVALID-CLAIM)) {action: "paid", block: block-height, actor: tx-sender}) u10) (err ERR-INVALID-CLAIM)))
      (log-event claim-id "paid")
      (ok true)
    )
  )
)

;; Dispute a claim (escalate to DAO)
(define-public (dispute-claim (claim-id uint) (reason (buff 512)))
  (begin
    (ensure-not-paused)
    (asserts! (> claim-id u0) (err ERR-INVALID-CLAIM))
    (let ((claim (unwrap! (map-get? claims claim-id) (err ERR-INVALID-CLAIM))))
      (asserts! (or (is-eq (get state claim) CLAIM-STATE-PENDING) (is-eq (get state claim) CLAIM-STATE-VERIFIED)) (err ERR-CLAIM-ALREADY-PROCESSED))
      (let ((dao-response (as-contract (contract-call? (var-get dao-contract) escalate-dispute claim-id tx-sender reason))))
        (asserts! (is-ok dao-response) (err ERR-INVALID-CLAIM))
        (map-set claims claim-id (merge claim {state: CLAIM-STATE-DISPUTED}))
        (map-insert claim-history claim-id (unwrap! (as-max-len? (append (unwrap! (map-get? claim-history claim-id) (err ERR-INVALID-CLAIM)) {action: "disputed", block: block-height, actor: tx-sender}) u10) (err ERR-INVALID-CLAIM)))
        (log-event claim-id "disputed")
        (ok (unwrap! dao-response (err ERR-INVALID-CLAIM)))
      )
    )
  )
)

;; Reject a claim (after dispute or timeout)
(define-public (reject-claim (claim-id uint))
  (begin
    (asserts! (is-authorized) (err ERR-NOT-AUTHORIZED))
    (asserts! (> claim-id u0) (err ERR-INVALID-CLAIM))
    (let ((claim (unwrap! (map-get? claims claim-id) (err ERR-INVALID-CLAIM))))
      (asserts! (or (is-eq (get state claim) CLAIM-STATE-DISPUTED) (> (- block-height (get submit-block claim)) CLAIM-TIMEOUT-BLOCKS)) (err ERR-INVALID-STATE))
      (map-set claims claim-id (merge claim {state: CLAIM-STATE-REJECTED}))
      (map-insert claim-history claim-id (unwrap! (as-max-len? (append (unwrap! (map-get? claim-history claim-id) (err ERR-INVALID-CLAIM)) {action: "rejected", block: block-height, actor: tx-sender}) u10) (err ERR-INVALID-CLAIM)))
      (log-event claim-id "rejected")
      (ok true)
    )
  )
)

;; Read-only: get claim details
(define-read-only (get-claim (claim-id uint))
  (map-get? claims claim-id)
)

;; Read-only: get claim history
(define-read-only (get-claim-history (claim-id uint))
  (map-get? claim-history claim-id)
)

;; Read-only: get claim counter
(define-read-only (get-claim-counter)
  (ok (var-get claim-counter))
)

;; Read-only: is paused
(define-read-only (is-paused)
  (ok (var-get paused))
)

;; Read-only: get contracts
(define-read-only (get-contracts)
  (ok {pool: (var-get pool-contract), oracle: (var-get oracle-contract), dao: (var-get dao-contract)})
)

;; Read-only: get multi-admins
(define-read-only (get-multi-admins)
  (ok (var-get multi-admins))
)