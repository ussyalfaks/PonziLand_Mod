import { address_blacklist } from '$profileData';
import { areAddressesEquals } from './helpers';
import {
  PUBLIC_DOJO_TORII_URL,
  PUBLIC_SOCIALINK_URL,
} from '$env/static/public';
import data from '$profileData';
const BASE_TOKEN = data.mainCurrencyAddress;

const blackList = address_blacklist.map((e) => BigInt(e));

export async function getUserAddresses() {
  try {
    const res = await fetch(`${PUBLIC_DOJO_TORII_URL}/sql`, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: `SELECT address FROM "ponzi_land-AddressAuthorizedEvent"`,
    });

    const data = await res.json();
    return data;
  } catch (err) {
    console.error('Error fetching addresses:', err);
    return [];
  }
}

export async function getBuyEvents() {
  try {
    const res = await fetch(`${PUBLIC_DOJO_TORII_URL}/sql`, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: `SELECT buyer FROM "ponzi_land-LandBoughtEvent" `,
    });

    const data = await res.json();
    return data;
  } catch (err) {
    console.error('Error fetching addresses:', err);
    return [];
  }
}

export async function fetchTokenBalances() {
  try {
    const response = await fetch(`${PUBLIC_DOJO_TORII_URL}/sql`, {
      method: 'POST',
      headers: {
        'Content-Type': 'text/plain',
      },
      body: `
          WITH ranked_balances AS (
            SELECT
              account_address,
              contract_address,
              balance,
              ROW_NUMBER() OVER (PARTITION BY contract_address ORDER BY balance DESC) as rank
            FROM token_balances
          )
          SELECT account_address, contract_address, balance
          FROM ranked_balances
          WHERE rank <= 50 OR contract_address = '${BASE_TOKEN}'
          ORDER BY contract_address, balance DESC;
        `,
    });

    if (!response.ok) {
      throw new Error('Network response was not ok');
    }

    const data = await response.json();
    return parseTokenBalances(data);
  } catch (error) {
    console.error('Error fetching token balances:', error);
    return {};
  }
}

interface TokenBalanceEntry {
  account_address: string;
  contract_address: string;
  balance: number;
}

export function parseTokenBalances(
  data: TokenBalanceEntry[],
): Record<string, Record<string, number>> {
  const result: Record<string, Record<string, number>> = {};

  data.forEach((entry) => {
    const { account_address, contract_address, balance } = entry;

    if (blackList.includes(BigInt(account_address))) {
      return;
    }

    if (!result[account_address]) {
      result[account_address] = {};
    }

    result[account_address][contract_address] = balance;
  });

  return result;
}

/**
 * @notice Fetches usernames for multiple addresses in a single batch request
 * @dev Uses Socialink API to get usernames for all provided addresses
 * @param addresses Array of wallet addresses to look up
 * @returns Record mapping addresses to usernames (if found)
 */
// TODO: Replace this with a direct SDK call
export async function fetchUsernamesBatch(
  addresses: string[],
): Promise<Record<string, string>> {
  try {
    const response = await fetch(`${PUBLIC_SOCIALINK_URL}/api/user/lookup`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ addresses }),
    });

    if (!response.ok) {
      throw new Error(`Network response was not ok: ${response.status}`);
    }

    const users = await response.json();
    const usernameMap: Record<string, string> = {};

    // Map the response to an address -> username lookup object
    users.forEach((user: { address: string; username: string }) => {
      if (user.username) {
        usernameMap[user.address] = user.username;
      }
    });

    return usernameMap;
  } catch (error) {
    console.error('Error fetching usernames in batch:', error);
    return {};
  }
}
