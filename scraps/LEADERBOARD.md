# Leaderboard
## Objective
Here's the different categories we need need to score on:
- Top Tax Lord (most taxes farmed), top 5
- Land Baron (most lands bought)
  - Land bought from auctions, top 3
  - Land bought from users, top 2
- Tax Dodger (lowest ratio of taxes paid relative to amount price paid to buy lands), top 5
  - only take users from the top 60
- Biggest Loser (highest ratio of taxes paid relative to amount price paid to buy lands), top 5
  - only take users from the top 60
- Amount of BTC owned, top 5
### Note
We need to filter users that does not have at least 30 transactions


## Principles
### Most taxes farmed
- Add up all the transfers from the contract to the users
- Substract the price of the land that were bought from you
- Substract the remaining stake in the Land
  - take the closest RemainingStakeEvent for the land before the buy (should be at the same moment as the buy event)
### Land Baron
- Easy to compute. Take all historical events for land buy, and count by user.
### Tax Dodger + Biggest Loser
- Both use the same metric, only the order changes.
- Computing the amount of taxes paid is a bit more involved.
  - Two situations:
    - Land is nuked, in that case, you just get the initial staked amount for the land
    - Land is bought, in that case, use the initial amount - the remaining amount at sell time
### Amount of BTC owned
- Easy, check balances, and take the higest amount that is not the AI.

## Implementation
1. First step, import all events & data we might want to use:
  - Import all events into distinct tables
  - Import all transfers into a table (with a numeric datatype)
  - Import all balances into a table (with a numeric datatype)
  - Import all lands + lands stake (with historical state) into their own tables
2. Generate some values from the various data.
  - For each historical land, we need to generate a LandSummary, that has:
    - Owner
    - Token used
    - Initial Stake
    - Final Stake (if bought)
