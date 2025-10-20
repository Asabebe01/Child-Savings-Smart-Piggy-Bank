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
(define-constant ERR-ACHIEVEMENT-NOT-FOUND (err u1009))
(define-constant ERR-ACHIEVEMENT-ALREADY-UNLOCKED (err u1010))
(define-constant ERR-INSUFFICIENT-PROGRESS (err u1011))
(define-constant ERR-CONTENT-LOCKED (err u1012))
(define-constant ERR-INVALID-LESSON (err u1013))
(define-constant ERR-INTEREST-ALREADY-CLAIMED (err u1014))
(define-constant ERR-NO-INTEREST-ACCRUED (err u1015))

(define-constant ACHIEVEMENT-REWARD-BASE u10)
(define-constant EDUCATIONAL-BONUS-MULTIPLIER u150)
(define-constant MAX-LESSON-LEVEL u10)
(define-constant MILESTONE-THRESHOLD-1 u100000)
(define-constant MILESTONE-THRESHOLD-2 u500000)
(define-constant MILESTONE-THRESHOLD_3 u1000000)

(define-constant BLOCKS-PER-YEAR u52560)
(define-constant MIN-MATURITY-YEARS u1)
(define-constant MAX-MATURITY-YEARS u25)
(define-constant EMERGENCY-PENALTY-PERCENT u10)
(define-constant INTEREST-RATE-TIER1 u200)
(define-constant INTEREST-RATE-TIER2 u350)
(define-constant INTEREST-RATE-TIER3 u500)
(define-constant INTEREST-CALCULATION-BLOCKS u52560)
(define-constant INTEREST-CLAIM-COOLDOWN u1440)

(define-data-var contract-owner principal tx-sender)
(define-data-var total-accounts uint u0)
(define-data-var total-deposits uint u0)
(define-data-var total-achievements-unlocked uint u0)
(define-data-var next-achievement-id uint u1)
(define-data-var total-interest-paid uint u0)

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

(define-map learning-achievements
  { achievement-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    achievement-type: (string-ascii 20),
    threshold-amount: uint,
    reward-tokens: uint,
    educational-content: (string-ascii 300),
    unlock-level: uint,
    active: bool
  }
)

(define-map child-achievements
  { child: principal, achievement-id: uint }
  {
    unlocked-at: uint,
    reward-claimed: bool,
    progress-percent: uint
  }
)

(define-map educational-progress
  { child: principal }
  {
    total-saved: uint,
    savings-streak: uint,
    lessons-completed: uint,
    current-level: uint,
    total-achievements: uint,
    learning-points: uint,
    last-activity: uint
  }
)

(define-map financial-lessons
  { lesson-id: uint }
  {
    title: (string-ascii 60),
    content: (string-ascii 400),
    lesson-type: (string-ascii 20),
    required-level: uint,
    reward-points: uint,
    completion-threshold: uint
  }
)

(define-map lesson-completion
  { child: principal, lesson-id: uint }
  {
    completed-at: uint,
    score: uint,
    points-earned: uint
  }
)

(define-map interest-tracking
  { child: principal }
  {
    last-claim-block: uint,
    total-interest-earned: uint,
    interest-tier: uint,
    compound-start-block: uint
  }
)

(define-read-only (get-learning-achievement (achievement-id uint))
  (map-get? learning-achievements { achievement-id: achievement-id })
)

(define-read-only (get-child-achievement (child principal) (achievement-id uint))
  (map-get? child-achievements { child: child, achievement-id: achievement-id })
)

(define-read-only (get-child-educational-progress (child principal))
  (get-educational-progress child)
)

(define-read-only (get-financial-lesson (lesson-id uint))
  (map-get? financial-lessons { lesson-id: lesson-id })
)

(define-read-only (get-lesson-completion (child principal) (lesson-id uint))
  (map-get? lesson-completion { child: child, lesson-id: lesson-id })
)

(define-read-only (get-child-learning-summary (child principal))
  (let ((progress-data (get-educational-progress child)))
    (ok {
      current-level: (get current-level progress-data),
      total-achievements: (get total-achievements progress-data),
      lessons-completed: (get lessons-completed progress-data),
      learning-points: (get learning-points progress-data),
      savings-streak: (get savings-streak progress-data),
      next-level-threshold: (get-next-level-threshold (get current-level progress-data))
    })
  )
)

(define-read-only (check-achievement-eligibility (child principal) (achievement-id uint))
  (let 
    (
      (achievement-data (map-get? learning-achievements { achievement-id: achievement-id }))
      (progress-data (get-educational-progress child))
      (existing-unlock (map-get? child-achievements { child: child, achievement-id: achievement-id }))
    )
    (match achievement-data
      achievement
      (ok {
        eligible: (and 
          (is-none existing-unlock)
          (get active achievement)
          (>= (get current-level progress-data) (get unlock-level achievement))
          (>= (calculate-achievement-progress child achievement-id) u100)
        ),
        progress-percent: (calculate-achievement-progress child achievement-id),
        required-level: (get unlock-level achievement),
        current-level: (get current-level progress-data)
      })
      ERR-ACHIEVEMENT-NOT-FOUND
    )
  )
)

(define-read-only (get-available-lessons (child principal))
  (let ((progress-data (get-educational-progress child)))
    (ok {
      current-level: (get current-level progress-data),
      available-lesson-ids: (list u1 u2 u3 u4 u5),
      completed-lessons: (get lessons-completed progress-data)
    })
  )
)

(define-read-only (get-educational-stats)
  {
    total-achievements-unlocked: (var-get total-achievements-unlocked),
    next-achievement-id: (var-get next-achievement-id)
  }
)

(define-private (get-next-level-threshold (current-level uint))
  (if (is-eq current-level u1) u10000
    (if (is-eq current-level u2) u50000
      (if (< current-level u5) MILESTONE-THRESHOLD-1
        (if (< current-level u7) MILESTONE-THRESHOLD-2
          (if (< current-level u10) MILESTONE-THRESHOLD_3
            u2000000)))))
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

(define-public (create-learning-achievement
  (name (string-ascii 50))
  (description (string-ascii 200))
  (achievement-type (string-ascii 20))
  (threshold-amount uint)
  (reward-tokens uint)
  (educational-content (string-ascii 300))
  (unlock-level uint)
)
  (let ((achievement-id (var-get next-achievement-id)))
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> threshold-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> reward-tokens u0) ERR-INVALID-AMOUNT)
    (asserts! (<= unlock-level MAX-LESSON-LEVEL) ERR-INVALID-LESSON)
    
    (map-set learning-achievements
      { achievement-id: achievement-id }
      {
        name: name,
        description: description,
        achievement-type: achievement-type,
        threshold-amount: threshold-amount,
        reward-tokens: reward-tokens,
        educational-content: educational-content,
        unlock-level: unlock-level,
        active: true
      })
    
    (var-set next-achievement-id (+ achievement-id u1))
    (ok achievement-id)
  )
)

(define-public (unlock-achievement (child principal) (achievement-id uint))
  (let 
    (
      (achievement-data (unwrap! (map-get? learning-achievements { achievement-id: achievement-id }) ERR-ACHIEVEMENT-NOT-FOUND))
      (progress-data (get-educational-progress child))
      (existing-unlock (map-get? child-achievements { child: child, achievement-id: achievement-id }))
    )
    (asserts! (is-none existing-unlock) ERR-ACHIEVEMENT-ALREADY-UNLOCKED)
    (asserts! (get active achievement-data) ERR-ACHIEVEMENT-NOT-FOUND)
    (asserts! (>= (get current-level progress-data) (get unlock-level achievement-data)) ERR-INSUFFICIENT-PROGRESS)
    
    (let 
      (
        (account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
        (progress-percent (calculate-achievement-progress child achievement-id))
        (reward-amount (get reward-tokens achievement-data))
      )
      (asserts! (>= progress-percent u100) ERR-INSUFFICIENT-PROGRESS)
      
      (begin
        (map-set child-achievements
          { child: child, achievement-id: achievement-id }
          {
            unlocked-at: stacks-block-height,
            reward-claimed: false,
            progress-percent: progress-percent
          })
        
        (map-set savings-accounts
          { child: child }
          (merge account-data { balance: (+ (get balance account-data) reward-amount) }))
        
        (unwrap-panic (update-educational-progress child "achievement-unlocked" reward-amount))
        (var-set total-achievements-unlocked (+ (var-get total-achievements-unlocked) u1))
        
        (unwrap-panic (add-transaction-record child reward-amount "achievement-reward" (get name achievement-data)))
        
        (ok {
          achievement-name: (get name achievement-data),
          reward-earned: reward-amount,
          educational-content: (get educational-content achievement-data)
        })
      )
    )
  )
)

(define-public (complete-financial-lesson (child principal) (lesson-id uint) (score uint))
  (let 
    (
      (lesson-data (unwrap! (map-get? financial-lessons { lesson-id: lesson-id }) ERR-INVALID-LESSON))
      (progress-data (get-educational-progress child))
      (existing-completion (map-get? lesson-completion { child: child, lesson-id: lesson-id }))
    )
    (asserts! (is-none existing-completion) ERR-ACHIEVEMENT-ALREADY-UNLOCKED)
    (asserts! (>= (get current-level progress-data) (get required-level lesson-data)) ERR-CONTENT-LOCKED)
    (asserts! (>= score (get completion-threshold lesson-data)) ERR-INSUFFICIENT-PROGRESS)
    
    (let 
      (
        (account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
        (points-earned (get reward-points lesson-data))
        (bonus-amount (/ (* points-earned ACHIEVEMENT-REWARD-BASE) u100))
      )
      (begin
        (map-set lesson-completion
          { child: child, lesson-id: lesson-id }
          {
            completed-at: stacks-block-height,
            score: score,
            points-earned: points-earned
          })
        
        (map-set savings-accounts
          { child: child }
          (merge account-data { balance: (+ (get balance account-data) bonus-amount) }))
        
        (unwrap-panic (update-educational-progress child "lesson-completed" points-earned))
        
        (unwrap-panic (add-transaction-record child bonus-amount "lesson-reward" (get title lesson-data)))
        
        (ok {
          lesson-title: (get title lesson-data),
          score-achieved: score,
          points-earned: points-earned,
          bonus-amount: bonus-amount
        })
      )
    )
  )
)

(define-public (create-financial-lesson
  (lesson-id uint)
  (title (string-ascii 60))
  (content (string-ascii 400))
  (lesson-type (string-ascii 20))
  (required-level uint)
  (reward-points uint)
  (completion-threshold uint)
)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= required-level MAX-LESSON-LEVEL) ERR-INVALID-LESSON)
    (asserts! (> reward-points u0) ERR-INVALID-AMOUNT)
    (asserts! (<= completion-threshold u100) ERR-INVALID-AMOUNT)
    
    (map-set financial-lessons
      { lesson-id: lesson-id }
      {
        title: title,
        content: content,
        lesson-type: lesson-type,
        required-level: required-level,
        reward-points: reward-points,
        completion-threshold: completion-threshold
      })
    
    (ok lesson-id)
  )
)

(define-public (grant-educational-bonus (child principal) (bonus-amount uint) (reason (string-ascii 50)))
  (let ((account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> bonus-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (begin
      (try! (stx-transfer? bonus-amount tx-sender (as-contract tx-sender)))
      
      (map-set savings-accounts
        { child: child }
        (merge account-data { balance: (+ (get balance account-data) bonus-amount) }))
      
      (unwrap-panic (update-educational-progress child "educational-bonus" bonus-amount))
      (var-set total-deposits (+ (var-get total-deposits) bonus-amount))
      
      (unwrap-panic (add-transaction-record child bonus-amount "educational-bonus" reason))
      
      (ok {
        bonus-granted: bonus-amount,
        reason: reason,
        new-balance: (+ (get balance account-data) bonus-amount)
      })
    )
  )
)

(define-private (update-educational-progress (child principal) (activity-type (string-ascii 20)) (amount uint))
  (let 
    (
      (current-progress (get-educational-progress child))
      (new-total-saved (+ (get total-saved current-progress) amount))
      (new-level (calculate-learning-level new-total-saved))
      (points-earned (calculate-learning-points activity-type amount))
    )
    (map-set educational-progress
      { child: child }
      {
        total-saved: new-total-saved,
        savings-streak: (calculate-savings-streak child),
        lessons-completed: (if (is-eq activity-type "lesson-completed") 
                            (+ (get lessons-completed current-progress) u1)
                            (get lessons-completed current-progress)),
        current-level: new-level,
        total-achievements: (if (is-eq activity-type "achievement-unlocked")
                             (+ (get total-achievements current-progress) u1)
                             (get total-achievements current-progress)),
        learning-points: (+ (get learning-points current-progress) points-earned),
        last-activity: stacks-block-height
      })
    (ok true)
  )
)

(define-private (calculate-achievement-progress (child principal) (achievement-id uint))
  (let 
    (
      (achievement-data (map-get? learning-achievements { achievement-id: achievement-id }))
      (account-data (map-get? savings-accounts { child: child }))
    )
    (match achievement-data
      achievement
      (match account-data
        account
        (let 
          (
            (current-balance (get balance account))
            (threshold (get threshold-amount achievement))
          )
          (if (>= current-balance threshold)
            u100
            (/ (* current-balance u100) threshold))
        )
        u0)
      u0)
  )
)

(define-private (calculate-learning-level (total-saved uint))
  (if (>= total-saved MILESTONE-THRESHOLD_3) u10
    (if (>= total-saved MILESTONE-THRESHOLD-2) u7
      (if (>= total-saved MILESTONE-THRESHOLD-1) u5
        (if (>= total-saved u50000) u3
          (if (>= total-saved u10000) u2 u1))))))

(define-private (calculate-learning-points (activity-type (string-ascii 20)) (amount uint))
  (if (is-eq activity-type "deposit")
    (/ amount u1000)
    (if (is-eq activity-type "lesson-completed")
      amount
      (if (is-eq activity-type "achievement-unlocked")
        (* amount u2)
        u0))))

(define-private (calculate-savings-streak (child principal))
  (let 
    (
      (account-data (unwrap! (map-get? savings-accounts { child: child }) u0))
      (current-progress (get-educational-progress child))
      (blocks-since-last (- stacks-block-height (get last-activity current-progress)))
    )
    (if (<= blocks-since-last u1440)
      (+ (get savings-streak current-progress) u1)
      u1)
  )
)

(define-private (get-educational-progress (child principal))
  (default-to
    {
      total-saved: u0,
      savings-streak: u0,
      lessons-completed: u0,
      current-level: u1,
      total-achievements: u0,
      learning-points: u0,
      last-activity: stacks-block-height
    }
    (map-get? educational-progress { child: child })
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
    (unwrap-panic (update-educational-progress child "deposit" amount))
    
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

(define-read-only (get-interest-info (child principal))
  (map-get? interest-tracking { child: child })
)

(define-read-only (calculate-interest-tier (maturity-years uint))
  (if (>= maturity-years u10) u3
    (if (>= maturity-years u5) u2 u1))
)

(define-read-only (get-interest-rate (tier uint))
  (if (is-eq tier u3) INTEREST-RATE-TIER3
    (if (is-eq tier u2) INTEREST-RATE-TIER2 INTEREST-RATE-TIER1))
)

(define-read-only (calculate-accrued-interest (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data
      (let 
        (
          (interest-data (default-to 
            { last-claim-block: (get created-at account-data), total-interest-earned: u0, interest-tier: u1, compound-start-block: (get created-at account-data) }
            (map-get? interest-tracking { child: child })))
          (current-balance (get balance account-data))
          (blocks-elapsed (- stacks-block-height (get last-claim-block interest-data)))
          (interest-rate (get-interest-rate (get interest-tier interest-data)))
          (interest-amount (/ (* (* current-balance interest-rate) blocks-elapsed) (* u10000 INTEREST-CALCULATION-BLOCKS)))
        )
        (ok {
          accrued-interest: interest-amount,
          current-balance: current-balance,
          blocks-since-last-claim: blocks-elapsed,
          interest-rate: interest-rate,
          interest-tier: (get interest-tier interest-data),
          can-claim: (>= blocks-elapsed INTEREST-CLAIM-COOLDOWN)
        })
      )
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-read-only (get-interest-projection (child principal) (future-blocks uint))
  (match (map-get? savings-accounts { child: child })
    account-data
      (let 
        (
          (interest-data (default-to 
            { last-claim-block: (get created-at account-data), total-interest-earned: u0, interest-tier: u1, compound-start-block: (get created-at account-data) }
            (map-get? interest-tracking { child: child })))
          (current-balance (get balance account-data))
          (interest-rate (get-interest-rate (get interest-tier interest-data)))
          (projected-interest (/ (* (* current-balance interest-rate) future-blocks) (* u10000 INTEREST-CALCULATION-BLOCKS)))
        )
        (ok {
          current-balance: current-balance,
          projected-interest: projected-interest,
          future-balance: (+ current-balance projected-interest),
          blocks-projected: future-blocks,
          annual-rate: interest-rate
        })
      )
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-read-only (get-compound-stats (child principal))
  (match (map-get? savings-accounts { child: child })
    account-data
      (match (map-get? interest-tracking { child: child })
        interest-data
        (ok {
          total-interest-earned: (get total-interest-earned interest-data),
          interest-tier: (get interest-tier interest-data),
          compound-duration: (- stacks-block-height (get compound-start-block interest-data)),
          last-claim-block: (get last-claim-block interest-data),
          next-claim-available: (+ (get last-claim-block interest-data) INTEREST-CLAIM-COOLDOWN)
        })
        (ok {
          total-interest-earned: u0,
          interest-tier: u1,
          compound-duration: u0,
          last-claim-block: (get created-at account-data),
          next-claim-available: (+ (get created-at account-data) INTEREST-CLAIM-COOLDOWN)
        })
      )
    ERR-ACCOUNT-NOT-FOUND
  )
)

(define-public (initialize-interest-account (child principal))
  (let 
    (
      (account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
      (existing-interest (map-get? interest-tracking { child: child }))
      (years-to-maturity (/ (- (get maturity-block account-data) stacks-block-height) BLOCKS-PER-YEAR))
      (interest-tier (calculate-interest-tier years-to-maturity))
    )
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-interest) ERR-ACCOUNT-EXISTS)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    
    (map-set interest-tracking
      { child: child }
      {
        last-claim-block: stacks-block-height,
        total-interest-earned: u0,
        interest-tier: interest-tier,
        compound-start-block: stacks-block-height
      })
    
    (unwrap-panic (add-transaction-record child u0 "interest-enabled" "Compound interest activated"))
    
    (ok {
      interest-tier: interest-tier,
      annual-rate: (get-interest-rate interest-tier),
      compound-start-block: stacks-block-height
    })
  )
)

(define-public (claim-interest (child principal))
  (let 
    (
      (account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
      (interest-data (unwrap! (map-get? interest-tracking { child: child }) ERR-ACCOUNT-NOT-FOUND))
      (blocks-elapsed (- stacks-block-height (get last-claim-block interest-data)))
      (interest-calculation (unwrap! (calculate-accrued-interest child) ERR-NO-INTEREST-ACCRUED))
      (interest-amount (get accrued-interest interest-calculation))
    )
    (asserts! (or (is-eq tx-sender (get parent account-data)) (is-eq tx-sender child)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (>= blocks-elapsed INTEREST-CLAIM-COOLDOWN) ERR-INTEREST-ALREADY-CLAIMED)
    (asserts! (> interest-amount u0) ERR-NO-INTEREST-ACCRUED)
    
    (map-set savings-accounts
      { child: child }
      (merge account-data { balance: (+ (get balance account-data) interest-amount) }))
    
    (map-set interest-tracking
      { child: child }
      {
        last-claim-block: stacks-block-height,
        total-interest-earned: (+ (get total-interest-earned interest-data) interest-amount),
        interest-tier: (get interest-tier interest-data),
        compound-start-block: (get compound-start-block interest-data)
      })
    
    (var-set total-interest-paid (+ (var-get total-interest-paid) interest-amount))
    (unwrap-panic (add-transaction-record child interest-amount "interest-claimed" "Compound interest added"))
    
    (ok {
      interest-earned: interest-amount,
      new-balance: (+ (get balance account-data) interest-amount),
      total-lifetime-interest: (+ (get total-interest-earned interest-data) interest-amount)
    })
  )
)

(define-public (upgrade-interest-tier (child principal))
  (let 
    (
      (account-data (unwrap! (map-get? savings-accounts { child: child }) ERR-ACCOUNT-NOT-FOUND))
      (interest-data (unwrap! (map-get? interest-tracking { child: child }) ERR-ACCOUNT-NOT-FOUND))
      (years-to-maturity (/ (- (get maturity-block account-data) stacks-block-height) BLOCKS-PER-YEAR))
      (new-tier (calculate-interest-tier years-to-maturity))
      (current-tier (get interest-tier interest-data))
    )
    (asserts! (is-eq tx-sender (get parent account-data)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active account-data) ERR-NOT-AUTHORIZED)
    (asserts! (> new-tier current-tier) ERR-INVALID-AMOUNT)
    
    (try! (claim-interest child))
    
    (map-set interest-tracking
      { child: child }
      (merge interest-data { interest-tier: new-tier }))
    
    (unwrap-panic (add-transaction-record child u0 "tier-upgraded" "Interest tier upgraded"))
    
    (ok {
      old-tier: current-tier,
      new-tier: new-tier,
      new-rate: (get-interest-rate new-tier)
    })
  )
)
