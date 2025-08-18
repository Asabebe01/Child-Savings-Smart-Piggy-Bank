;; title: Child-smart-savings
;; version: 1.0.0
;; summary: Smart piggy bank for children with age-locked savings
;; description: Parents can deposit STX tokens that unlock when child reaches maturity age

(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-ACCOUNT-NOT-FOUND (err u1002))
(define-constant ERR-ACCOUNT-EXISTS (err u1003))
(define-constant ERR-NOT-MATURE (err u1004))
(define-constant ERR-INVALID-AMOUNT (err u1005))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1006))
(define-constant ERR-INVALID-MATURITY (err u1007))
(define-constant ERR-TRANSFER-FAILED (err u1008))

(define-constant BLOCKS-PER-YEAR u52560)
(define-constant MIN-MATURITY-YEARS u1)
(define-constant MAX-MATURITY-YEARS u25)
(define-constant EMERGENCY-PENALTY-PERCENT u10)

(define-data-var contract-owner principal tx-sender)
(define-data-var total-accounts uint u0)
(define-data-var total-deposits uint u0)

(define-map savings-accounts
  { child: principal }
  {
    parent: principal,
    balance: uint,
    maturity-block: uint,
    created-at: uint,
    goal-amount: uint,
    milestone-description: (string-ascii 256),
    is-active: bool
  }
)

(define-map account-transactions
  { child: principal, transaction-id: uint }
  {
    amount: uint,
    transaction-type: (string-ascii 20),
    block-height: uint,
    description: (string-ascii 256)
  }
)

(define-map transaction-counters
  { child: principal }
  { count: uint }
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-account-info (child principal))
  (map-get? savings-accounts { child: child })
)

(define-read-only (get-total-stats)
  {
    total-accounts: (var-get total-accounts),
    total-deposits: (var-get total-deposits)
  }
)

(define-read-only (get-transaction-count (child principal))
  (default-to u0 (get count (map-get? transaction-counters { child: child })))
)

(define-read-only (get-transaction (child principal) (tx-id uint))
  (map-get? account-transactions { child: child, transaction-id: tx-id })
)

(define-read-only (is-account-mature (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data (>= stacks-block-height (get maturity-block account-data))
    false
  )
)

(define-read-only (calculate-maturity-block (years uint))
  (+ stacks-block-height (* years BLOCKS-PER-YEAR))
)

(define-read-only (get-blocks-until-maturity (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data 
      (if (>= stacks-block-height (get maturity-block account-data))
        u0
        (- (get maturity-block account-data) stacks-block-height))
    u0
  )
)

(define-read-only (get-goal-progress (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data 
      (ok {
        current-balance: (get balance account-data),
        goal-amount: (get goal-amount account-data),
        progress-percent: (/ (* (get balance account-data) u100) (get goal-amount account-data)),
        milestone-description: (get milestone-description account-data),
        is-goal-reached: (>= (get balance account-data) (get goal-amount account-data))
      })
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-read-only (get-maturity-info (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data
      (ok {
        maturity-block: (get maturity-block account-data),
        current-block: stacks-block-height,
        blocks-remaining: (get-blocks-until-maturity child),
        is-mature: (is-account-mature child),
        years-created: (/ (- stacks-block-height (get created-at account-data)) BLOCKS-PER-YEAR)
      })
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-read-only (calculate-emergency-withdrawal (child principal) (amount uint))
  (match (map-get? savings-accounts { child: child })
    account-data
      (let ((penalty (/ (* amount EMERGENCY-PENALTY-PERCENT) u100)))
        (ok {
          requested-amount: amount,
          penalty-amount: penalty,
          net-withdrawal: (- amount penalty),
          penalty-percent: EMERGENCY-PENALTY-PERCENT
        })
      )
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-private (add-transaction-record (child principal) (amount uint) (tx-type (string-ascii 20)) (description (string-ascii 256)))
  (let ((current-count (get-transaction-count child)))
    (begin
      (map-set account-transactions
        { child: child, transaction-id: current-count }
        {
          amount: amount,
          transaction-type: tx-type,
          block-height: stacks-block-height,
          description: description
        }
      )
      (map-set transaction-counters
        { child: child }
        { count: (+ current-count u1) }
      )
      (ok true)
    )
  )
)

(define-public (create-savings-account 
    (child principal) 
    (maturity-years uint) 
    (goal-amount uint) 
    (milestone-description (string-ascii 256)))
  (let ((maturity-block (calculate-maturity-block maturity-years)))
    (asserts! (and (>= maturity-years MIN-MATURITY-YEARS) (<= maturity-years MAX-MATURITY-YEARS)) ERR-INVALID-MATURITY)
    (asserts! (> goal-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? savings-accounts { child: child })) ERR-ACCOUNT-EXISTS)
    
    (map-set savings-accounts
      { child: child }
      {
        parent: tx-sender,
        balance: u0,
        maturity-block: maturity-block,
        created-at: stacks-block-height,
        goal-amount: goal-amount,
        milestone-description: milestone-description,
        is-active: true
      }
    )
    
    (var-set total-accounts (+ (var-get total-accounts) u1))
    (unwrap-panic (add-transaction-record child u0 "account-created" milestone-description))
    
    (ok {
      child: child,
      maturity-block: maturity-block,
      years-to-maturity: maturity-years,
      goal-amount: goal-amount
    })
  )
)

(define-public (deposit-to-savings (child principal) (amount uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { balance: (+ (get balance account-data) amount) })
    )
    
    (var-set total-deposits (+ (var-get total-deposits) amount))
    (unwrap-panic (add-transaction-record child amount "deposit" "Parent deposit"))
    
    (ok {
      new-balance: (+ (get balance account-data) amount),
      deposited: amount,
      goal-progress: (/ (* (+ (get balance account-data) amount) u100) (get goal-amount account-data))
    })
  )
)

(define-public (withdraw-savings (amount uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: tx-sender }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get balance account-data) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (is-account-mature tx-sender) ERR-NOT-MATURE)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set savings-accounts
      { child: tx-sender }
      (merge account-data { balance: (- (get balance account-data) amount) })
    )
    
    (unwrap-panic (add-transaction-record tx-sender amount "withdrawal" "Mature withdrawal"))
    
    (ok {
      withdrawn: amount,
      remaining-balance: (- (get balance account-data) amount)
    })
  )
)

(define-public (emergency-withdrawal (child principal) (amount uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
        (penalty-amount (/ (* amount EMERGENCY-PENALTY-PERCENT) u100))
        (withdrawal-amount (- amount penalty-amount)))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get balance account-data) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { balance: (- (get balance account-data) amount) })
    )
    
    (unwrap-panic (add-transaction-record child amount "emergency-withdrawal" "Emergency withdrawal with penalty"))
    
    (ok {
      withdrawn: withdrawal-amount,
      penalty: penalty-amount,
      remaining-balance: (- (get balance account-data) amount)
    })
  )
)

(define-public (update-goal (child principal) (new-goal uint) (new-description (string-ascii 256)))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> new-goal u0) ERR-INVALID-AMOUNT)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { 
        goal-amount: new-goal,
        milestone-description: new-description
      })
    )
    
    (unwrap-panic (add-transaction-record child u0 "goal-updated" new-description))
    
    (ok {
      new-goal: new-goal,
      new-description: new-description,
      current-progress: (/ (* (get balance account-data) u100) new-goal)
    })
  )
)

(define-public (extend-maturity (child principal) (additional-years uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
        (additional-blocks (* additional-years BLOCKS-PER-YEAR)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> additional-years u0) ERR-INVALID-AMOUNT)
    (asserts! (<= additional-years u10) ERR-INVALID-MATURITY)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (< stacks-block-height (get maturity-block account-data)) ERR-NOT-MATURE)
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { maturity-block: (+ (get maturity-block account-data) additional-blocks) })
    )
    
    (unwrap-panic (add-transaction-record child u0 "maturity-extended" "Maturity period extended"))
    
    (ok {
      new-maturity-block: (+ (get maturity-block account-data) additional-blocks),
      additional-years: additional-years
    })
  )
)

(define-public (close-account (child principal))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
        (balance (get balance account-data)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (if (> balance u0)
      (try! (as-contract (stx-transfer? balance tx-sender tx-sender)))
      true
    )
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { 
        balance: u0,
        is-active: false
      })
    )
    
    (unwrap-panic (add-transaction-record child balance "account-closed" "Account closed by parent"))
    
    (ok {
      refunded: balance,
      account-status: "closed"
    })
  )
)

(define-public (transfer-parentship (child principal) (new-parent principal))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq new-parent child)) ERR-NOT-AUTHORIZED)
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { parent: new-parent })
    )
    
    (unwrap-panic (add-transaction-record child u0 "parent-transferred" "Parentship transferred"))
    
    (ok {
      child: child,
      old-parent: (get parent account-data),
      new-parent: new-parent
    })
  )
)

(define-public (partial-withdrawal (amount uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: tx-sender }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get balance account-data) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (is-account-mature tx-sender) ERR-NOT-MATURE)
    (asserts! (>= (- (get balance account-data) amount) (/ (get goal-amount account-data) u4)) ERR-INSUFFICIENT-BALANCE)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set savings-accounts
      { child: tx-sender }
      (merge account-data { balance: (- (get balance account-data) amount) })
    )
    
    (unwrap-panic (add-transaction-record tx-sender amount "partial-withdrawal" "Partial mature withdrawal"))
    
    (ok {
      withdrawn: amount,
      remaining-balance: (- (get balance account-data) amount)
    })
  )
)

(define-public (set-milestone-reward (child principal) (reward-amount uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get balance account-data) (get goal-amount account-data)) ERR-INSUFFICIENT-BALANCE)
    
    (try! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)))
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { balance: (+ (get balance account-data) reward-amount) })
    )
    
    (unwrap-panic (add-transaction-record child reward-amount "milestone-reward" "Goal achievement reward"))
    
    (ok {
      reward-amount: reward-amount,
      new-balance: (+ (get balance account-data) reward-amount)
    })
  )
)

(define-public (batch-deposit (children (list 5 principal)) (amounts (list 5 uint)))
  (let ((results (map process-batch-deposit children amounts)))
    (ok results)
  )
)

(define-private (process-batch-deposit (child principal) (amount uint))
  (match (map-get? savings-accounts { child: child })
    account-data
      (if (and (is-eq tx-sender (get parent account-data)) (get is-active account-data))
        (match (stx-transfer? amount tx-sender (as-contract tx-sender))
          success
            (begin
              (map-set savings-accounts
                { child: child }
                (merge account-data { balance: (+ (get balance account-data) amount) })
              )
              (var-set total-deposits (+ (var-get total-deposits) amount))
              (unwrap-panic (add-transaction-record child amount "batch-deposit" "Batch deposit"))
              { child: child, deposited: amount, success: true }
            )
          error { child: child, deposited: u0, success: false }
        )
        { child: child, deposited: u0, success: false }
      )
    { child: child, deposited: u0, success: false }
  )
)

(define-public (auto-save-setup (child principal) (monthly-amount uint) (duration-months uint))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> monthly-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> duration-months u0) ERR-INVALID-AMOUNT)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (unwrap-panic (add-transaction-record child monthly-amount "auto-save-setup" "Auto-save plan created"))
    
    (ok {
      monthly-amount: monthly-amount,
      duration-months: duration-months,
      total-planned: (* monthly-amount duration-months)
    })
  )
)

(define-public (update-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok new-owner)
  )
)

(define-public (get-account-balance (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data (ok (get balance account-data))
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-public (check-withdrawal-eligibility (child principal) (amount uint))
  (match (map-get? savings-accounts { child: child })
    account-data
      (ok {
        can-withdraw: (and 
          (is-account-mature child)
          (>= (get balance account-data) amount)
          (get is-active account-data)
        ),
        is-mature: (is-account-mature child),
        sufficient-balance: (>= (get balance account-data) amount),
        account-active: (get is-active account-data),
        current-balance: (get balance account-data)
      })
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-read-only (get-contract-stats)
  {
    total-accounts: (var-get total-accounts),
    total-deposits: (var-get total-deposits),
    contract-owner: (var-get contract-owner),
    current-block: stacks-block-height
  }
)
