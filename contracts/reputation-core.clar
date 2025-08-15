;; Reputation Core Contract
;; Manages user reputation scores and core trust metrics

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-USER-NOT-FOUND (err u101))
(define-constant ERR-INVALID-SCORE (err u102))
(define-constant ERR-ALREADY-REGISTERED (err u103))
(define-constant ERR-INSUFFICIENT-STAKE (err u104))

;; Minimum STX required to register (1000 microSTX = 0.001 STX)
(define-constant MIN-STAKE-AMOUNT u1000)

;; Maximum reputation score
(define-constant MAX-REPUTATION u1000)

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-users uint u0)

;; Data Maps
(define-map user-profiles
  principal
  {
    reputation-score: uint,
    total-transactions: uint,
    successful-transactions: uint,
    total-reviews-given: uint,
    total-reviews-received: uint,
    disputes-created: uint,
    disputes-resolved-favorably: uint,
    registration-block: uint,
    stake-amount: uint,
    is-verified: bool,
    last-activity-block: uint
  }
)

(define-map user-stakes
  principal
  uint
)

;; Public Functions

;; Register a new user with minimum stake
(define-public (register-user (stake-amount uint))
  (let (
    (caller tx-sender)
    (current-block block-height)
  )
    ;; Fixed boolean assertion - removed incorrect get call
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (>= stake-amount MIN-STAKE-AMOUNT) ERR-INSUFFICIENT-STAKE)
    (asserts! (is-none (map-get? user-profiles caller)) ERR-ALREADY-REGISTERED)

    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))

    ;; Create user profile
    (map-set user-profiles caller {
      reputation-score: u500, ;; Start with neutral score
      total-transactions: u0,
      successful-transactions: u0,
      total-reviews-given: u0,
      total-reviews-received: u0,
      disputes-created: u0,
      disputes-resolved-favorably: u0,
      registration-block: current-block,
      stake-amount: stake-amount,
      is-verified: false,
      last-activity-block: current-block
    })

    ;; Record stake
    (map-set user-stakes caller stake-amount)

    ;; Increment total users
    (var-set total-users (+ (var-get total-users) u1))

    (ok true)
  )
)

;; Update user reputation score (only callable by other contracts)
(define-public (update-reputation (user principal) (score-change int))
  (let (
    (current-profile (unwrap! (map-get? user-profiles user) ERR-USER-NOT-FOUND))
    (current-score (get reputation-score current-profile))
    ;; replaced min function with conditional expression
    (new-score (if (>= score-change 0)
                   (let ((potential-score (+ current-score (to-uint score-change))))
                     (if (<= potential-score MAX-REPUTATION)
                         potential-score
                         MAX-REPUTATION))
                   (if (>= current-score (to-uint (- 0 score-change)))
                       (- current-score (to-uint (- 0 score-change)))
                       u0)))
  )
    (asserts! (is-contract-caller) ERR-NOT-AUTHORIZED)

    (map-set user-profiles user (merge current-profile {
      reputation-score: new-score,
      last-activity-block: block-height
    }))

    (ok new-score)
  )
)

;; Update transaction statistics
(define-public (update-transaction-stats (user principal) (successful bool))
  (let (
    (current-profile (unwrap! (map-get? user-profiles user) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-contract-caller) ERR-NOT-AUTHORIZED)

    (map-set user-profiles user (merge current-profile {
      total-transactions: (+ (get total-transactions current-profile) u1),
      successful-transactions: (if successful
                                   (+ (get successful-transactions current-profile) u1)
                                   (get successful-transactions current-profile)),
      last-activity-block: block-height
    }))

    (ok true)
  )
)

;; Update review statistics
(define-public (update-review-stats (reviewer principal) (reviewee principal))
  (let (
    (reviewer-profile (unwrap! (map-get? user-profiles reviewer) ERR-USER-NOT-FOUND))
    (reviewee-profile (unwrap! (map-get? user-profiles reviewee) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-contract-caller) ERR-NOT-AUTHORIZED)

    ;; Update reviewer stats
    (map-set user-profiles reviewer (merge reviewer-profile {
      total-reviews-given: (+ (get total-reviews-given reviewer-profile) u1),
      last-activity-block: block-height
    }))

    ;; Update reviewee stats
    (map-set user-profiles reviewee (merge reviewee-profile {
      total-reviews-received: (+ (get total-reviews-received reviewee-profile) u1),
      last-activity-block: block-height
    }))

    (ok true)
  )
)

;; Update dispute statistics
(define-public (update-dispute-stats (user principal) (resolved-favorably bool))
  (let (
    (current-profile (unwrap! (map-get? user-profiles user) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-contract-caller) ERR-NOT-AUTHORIZED)

    (map-set user-profiles user (merge current-profile {
      disputes-created: (+ (get disputes-created current-profile) u1),
      disputes-resolved-favorably: (if resolved-favorably
                                       (+ (get disputes-resolved-favorably current-profile) u1)
                                       (get disputes-resolved-favorably current-profile)),
      last-activity-block: block-height
    }))

    (ok true)
  )
)

;; Verify user (admin function)
(define-public (verify-user (user principal))
  (let (
    (current-profile (unwrap! (map-get? user-profiles user) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set user-profiles user (merge current-profile {
      is-verified: true
    }))

    (ok true)
  )
)

;; Read-only Functions

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles user)
)

;; Get user reputation score
(define-read-only (get-reputation-score (user principal))
  (match (map-get? user-profiles user)
    profile (some (get reputation-score profile))
    none
  )
)

;; Calculate success rate
(define-read-only (get-success-rate (user principal))
  (match (map-get? user-profiles user)
    profile (let (
      (total (get total-transactions profile))
      (successful (get successful-transactions profile))
    )
      (if (> total u0)
          (some (/ (* successful u100) total))
          (some u0)))
    none
  )
)

;; Check if user is registered
(define-read-only (is-user-registered (user principal))
  (is-some (map-get? user-profiles user))
)

;; Get total users
(define-read-only (get-total-users)
  (var-get total-users)
)

;; Get user stake amount
(define-read-only (get-user-stake (user principal))
  (map-get? user-stakes user)
)

;; Private Functions

;; Check if caller is a contract
(define-private (is-contract-caller)
  (not (is-eq tx-sender contract-caller))
)
