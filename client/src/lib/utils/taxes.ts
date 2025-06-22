import type { LandWithActions } from '$lib/api/land';
import { GAME_SPEED, GRID_SIZE, TAX_RATE } from '$lib/const';
import type { Token } from '$lib/interfaces';
import { toHexWithPadding } from '$lib/utils';
import data from '$profileData';
import { CurrencyAmount } from './CurrencyAmount';
export type TaxData = {
  tokenAddress: string;
  tokenSymbol: string;
  totalTax: CurrencyAmount;
};

export const getAggregatedTaxes = async (
  land: LandWithActions,
): Promise<{
  nukables: { location: string; nukable: boolean }[];
  taxes: TaxData[];
}> => {
  if (!land || !land.getNextClaim || !land.getPendingTaxes) {
    return {
      nukables: [],
      taxes: [],
    };
  }

  const locationsToNuke: { location: string; nukable: boolean }[] = [];

  // aggregate the two arrays with total tax per token
  const tokenTaxMap: Record<string, CurrencyAmount> = {};

  for (const tax of (await land.getNextClaim()) ?? []) {
    locationsToNuke.push({
      location: tax.landLocation,
      nukable: tax.canBeNuked,
    });

    if (tax.amount.isZero()) {
      continue;
    }

    const token: Token | undefined = data.availableTokens.find(
      (t) => t.address == tax.tokenAddress,
    );

    const tokenAddress = token?.address ?? tax.tokenAddress;

    tokenTaxMap[tokenAddress] = (
      tokenTaxMap[tokenAddress] || CurrencyAmount.fromScaled(0, token)
    ).add(tax.amount);
  }

  for (const tax of (await land.getPendingTaxes()) ?? []) {
    if (tax.amount.isZero()) {
      continue;
    }

    const token: Token | undefined = data.availableTokens.find(
      (t) => t.address == tax.tokenAddress,
    );

    const tokenAddress = token?.address ?? tax.tokenAddress;

    tokenTaxMap[tokenAddress] = (
      tokenTaxMap[tokenAddress] || CurrencyAmount.fromScaled(0, token)
    ).add(tax.amount);
  }

  const taxes = Object.entries(tokenTaxMap).map(([tokenAddress, totalTax]) => {
    const token: Token | undefined = data.availableTokens.find(
      (t) => t.address == tokenAddress,
    );

    return {
      tokenAddress: tokenAddress,
      tokenSymbol: token?.symbol ?? '???',
      totalTax: totalTax,
    };
  });

  // Convert the map to an array of objects
  return {
    taxes,
    nukables: locationsToNuke,
  };
};

export const getNeighbourYieldArray = async (land: LandWithActions) => {
  const rawYieldInfos = await land.getYieldInfo();

  const location = Number(land.location);
  const neighbors = [
    location - GRID_SIZE - 1,
    location - GRID_SIZE,
    location - GRID_SIZE + 1,
    location - 1,
    location,
    location + 1,
    location + GRID_SIZE - 1,
    location + GRID_SIZE,
    location + GRID_SIZE + 1,
  ];

  // assign yield info to neighbour if location matches
  const neighborYieldInfo = neighbors.map((loc) => {
    const info = rawYieldInfos?.yield_info.find(
      (y) => y.location == BigInt(loc),
    );

    if (!info?.percent_rate) {
      return {
        ...info,
        token: undefined,
        location: BigInt(loc),
        sell_price: 0n,
        percent_rate: 0n,
        per_hour: 0n,
      };
    }

    const tokenAddress = toHexWithPadding(info?.token);
    const token = data.availableTokens.find((t) => t.address == tokenAddress);

    return {
      ...info,
      token,
    };
  });

  const infosFormatted = neighborYieldInfo.sort((a, b) => {
    return Number((a?.location ?? 0n) - (b?.location ?? 0n));
  });

  return infosFormatted;
};

export const estimateNukeTime = (
  land: LandWithActions,
  neighbourNumber: number | undefined = undefined,
) => {
  const baseTime = 3600;
  let sellPrice = land.sellPrice.rawValue().toNumber();
  let remainingStake = land.stakeAmount.rawValue().toNumber();
  let lastPayTime = Number(land.lastPayTime);

  if (!neighbourNumber) {
    neighbourNumber = land.getNeighbors().getNeighbors().length;
  }
  if (sellPrice <= 0 || isNaN(sellPrice)) {
    return 0;
  }
  const rateOfActualNeighbours = Number(
    calculateBurnRate(land, neighbourNumber),
  );

  const remainingHours = remainingStake / rateOfActualNeighbours;
  const remainingSeconds = remainingHours * baseTime;

  const now = Date.now() / 1000;
  const timeSinceLastPay = now - lastPayTime;
  const remainingNukeTimeFromNow = remainingSeconds - timeSinceLastPay;

  return remainingNukeTimeFromNow;
};

export const parseNukeTime = (givenTime: number) => {
  const time = givenTime / 60; // Convert seconds to minutes

  // Convert minutes (bigint) to days, hours, minutes, and seconds
  const minutes = Math.floor(time % 60);
  const hours = Math.floor((time / 60) % 24);
  const days = Math.floor(time / 1440); // 1440 minutes in a day

  // Build the formatted string
  const parts: string[] = [];

  if (days > 0) parts.push(`${days}d`);
  if (hours > 0 || days > 0)
    parts.push(`${hours.toString().padStart(2, '0')}h`);
  if (minutes > 0 || hours > 0 || days > 0)
    parts.push(`${minutes.toString().padStart(2, '0')}m`);

  return {
    minutes,
    hours,
    days,
    toString: () => parts.join(' '),
  };
};

export const estimateTax = (sellPrice: number) => {
  if (sellPrice <= 0 || isNaN(sellPrice)) {
    return {
      taxRate: 0,
      baseTime: 0,
      maxRate: 0,
      ratePerNeighbour: 0,
    };
  }

  const gameSpeed = GAME_SPEED;
  const taxRate = 0.02;
  const baseTime = 3600;
  const maxNeighbours = 8;

  const maxRate = sellPrice * taxRate * gameSpeed;
  const maxRatePerNeighbour = maxRate / maxNeighbours;

  return {
    taxRate,
    baseTime,
    maxRate,
    ratePerNeighbour: maxRatePerNeighbour,
  };
};

export function burnForOneNeighbor(land: LandWithActions) {
  const maxN = 8;
  return land.sellPrice
    .rawValue()
    .multipliedBy(TAX_RATE)
    .multipliedBy(GAME_SPEED)
    .dividedBy(maxN * 100);
}

// TODO: edge case land in the corners or edges of the map
export function calculateBurnRate(
  land: LandWithActions,
  neighborCount: number,
) {
  const discount_for_level = calculateDiscount(land.level);

  let base = burnForOneNeighbor(land).multipliedBy(neighborCount);

  if (discount_for_level > 0) {
    return base.multipliedBy(100 - discount_for_level).dividedBy(100);
  } else {
    return base;
  }
}

export function calculateTaxes(sellAmount: number) {
  const taxRate = TAX_RATE;
  const gameSpeed = GAME_SPEED;
  const maxN = 8;

  if (sellAmount <= 0 || isNaN(sellAmount)) {
    return 0;
  }

  const taxes = (sellAmount * taxRate * gameSpeed) / (maxN * 100);

  return taxes;
}

function calculateDiscount(level: number) {
  if (level == 1) {
    return 0;
  } else if (level == 2) {
    return 10;
  } else if (level == 3) {
    return 15;
  }
  return 0;
}
