# 🐷 Child Savings Smart Piggy Bank

A blockchain-based smart contract that enables parents to create secure savings accounts for their children with age-locked withdrawals and milestone tracking.

## 🎯 Features

- 👨‍👩‍👧‍👦 **Parent-Controlled Deposits**: Only parents can deposit STX tokens into their child's account
- 🔒 **Age-Locked Withdrawals**: Children can only withdraw funds after reaching maturity (1-25 years)
- 🎖️ **Milestone Tracking**: Set savings goals with custom descriptions  
- 💰 **Emergency Access**: Parents can withdraw with 10% penalty for emergencies
- 📊 **Progress Tracking**: Monitor savings progress toward goals
- 🔄 **Partial Withdrawals**: Children can make partial withdrawals after maturity
- 📈 **Transaction History**: Complete audit trail of all account activity
- 🎁 **Milestone Rewards**: Parents can add bonus rewards when goals are achieved

## 🚀 Quick Start

### Creating a Savings Account

```clarity
(contract-call? .Child-smart-savings create-savings-account 
  'ST1CHILD-PRINCIPAL     ;; child's address
  u18                     ;; maturity in years (18 years)
  u1000000               ;; goal amount in microSTX (1 STX)
  "College fund savings") ;; milestone description
```

### Making Deposits

```clarity
(contract-call? .Child-smart-savings deposit-to-savings 
  'ST1CHILD-PRINCIPAL  ;; child's address  
  u100000)             ;; amount in microSTX (0.1 STX)
```

### Withdrawing Funds (Child Only)

```clarity
(contract-call? .Child-smart-savings withdraw-savings 
  u500000)  ;; amount in microSTX (0.5 STX)
```

### Emergency Withdrawal (Parent Only)

```clarity
(contract-call? .Child-smart-savings emergency-withdrawal 
  'ST1CHILD-PRINCIPAL  ;; child's address
  u200000)             ;; amount (incurs 10% penalty)
```

## 📋 Contract Functions

### Public Functions

| Function | Description | Who Can Call |
|----------|-------------|--------------|
| `create-savings-account` | Create new savings account for child | Anyone (becomes parent) |
| `deposit-to-savings` | Deposit STX tokens into child's account | Parent only |
| `withdraw-savings` | Withdraw funds after maturity | Child only |
| `emergency-withdrawal` | Emergency withdrawal with penalty | Parent only |
| `update-goal` | Change savings goal and description | Parent only |
| `extend-maturity` | Add years to maturity period | Parent only |
| `close-account` | Close account and refund balance | Parent only |
| `transfer-parentship` | Transfer parent role to new address | Parent only |
| `partial-withdrawal` | Withdraw portion of mature funds | Child only |
| `set-milestone-reward` | Add bonus when goal is reached | Parent only |
| `batch-deposit` | Deposit to multiple children at once | Parent only |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-account-info` | Get complete account details |
| `get-goal-progress` | Check progress toward savings goal |
| `get-maturity-info` | Check maturity status and timeline |
| `is-account-mature` | Check if account has reached maturity |
| `get-transaction-history` | Get account transaction history |
| `calculate-emergency-withdrawal` | Preview emergency withdrawal amounts |
| `get-total-stats` | Get contract-wide statistics |

## 💡 Usage Examples

### 👨‍👩‍👧‍👦 Setting Up Your Child's Savings

```clarity
;; Create account for 10-year-old with 8-year maturity
(contract-call? .Child-smart-savings create-savings-account 
  'ST1CHILD123 u8 u5000000 "High school graduation fund")

;; Make initial deposit
(contract-call? .Child-smart-savings deposit-to-savings 'ST1CHILD123 u1000000)
```

### 📊 Checking Progress

```clarity
;; Check how close child is to their goal
(contract-call? .Child-smart-savings get-goal-progress 'ST1CHILD123)

;; Check when they can withdraw
(contract-call? .Child-smart-savings get-maturity-info 'ST1CHILD123)
```

### 🎁 Rewarding Milestones

```clarity
;; Add bonus when child reaches their savings goal
(contract-call? .Child-smart-savings set-milestone-reward 'ST1CHILD123 u500000)
```

## ⚠️ Important Notes

- 🔒 **Maturity Period**: 1-25 years, calculated in blocks (52,560 blocks ≈ 1 year)
- 💸 **Emergency Penalty**: 10% fee on emergency withdrawals by parents
- 🚫 **Withdrawal Restrictions**: Children must wait until maturity to access funds
- 📝 **Transaction Limits**: Partial withdrawals must leave 25% of goal amount
- 🔄 **Account Management**: Parents can close accounts and transfer parentship

## 🛠️ Development

### Prerequisites
- Clarinet installed
- Stacks blockchain knowledge

### Testing
```bash
clarinet check
clarinet test
```

### Deployment
```bash
clarinet deploy --testnet
```

## 📚 Technical Details

- **Clarity Version**: 3
- **Epoch**: 3.1  
- **Block Time**: ~10 minutes average
- **Maximum Children per Parent**: Unlimited
- **Maximum Goal Amount**: No limit (uint max)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

MIT License - see LICENSE file for details.
