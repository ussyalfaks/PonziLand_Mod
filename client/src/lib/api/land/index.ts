import type { LandYieldInfo, Token } from '$lib/interfaces';
import type { Auction, Land, LandStake } from '$lib/models.gen';
import {
  coordinatesToLocation,
  toHexWithPadding,
  getTokenInfo,
} from '$lib/utils';
import { CurrencyAmount } from '$lib/utils/CurrencyAmount';
import { type Level, fromDojoLevel } from '$lib/utils/level';
import type { BigNumberish } from 'starknet';
import type { CairoCustomEnum } from 'starknet';

import { Neighbors } from '../neighbors';
import { type Location } from './location';
import type { LandTileStore } from '../land_tiles.svelte';
export type LandType = 'empty' | 'building' | 'auction';

export type TransactionResult = Promise<
  | {
      transaction_hash: string;
    }
  | undefined
>;

export type PendingTax = {
  amount: CurrencyAmount;
  tokenAddress: string;
};

export type NextClaimInformation = {
  amount: CurrencyAmount;
  tokenAddress: string;
  landLocation: string;
  canBeNuked: boolean;
};

export type LevelInfo = {
  canLevelUp: boolean;
  expectedLevel: Level;
  timeSinceLastLevelUp: number;
  levelUpTime: number;
};

export type LandWithStake = Land & LandStake;
export type LandAuction = Land & Auction;

export type LandSetup = {
  tokenForSaleAddress: string;
  salePrice: CurrencyAmount;
  amountToStake: CurrencyAmount;
  tokenAddress: string;
  currentPrice: CurrencyAmount | null;
};

export type LandWithMeta = Omit<
  Land | LandWithStake | LandAuction,
  'location' | 'level'
> & {
  location: string;
  // Type conversions
  stakeAmount: CurrencyAmount;
  lastPayTime: number;
  sellPrice: CurrencyAmount;

  type: 'auction' | 'house' | 'grass';
  owner: string;

  level: Level;

  tokenUsed: string | null;
  tokenAddress: string | null;

  token?: Token;
};

export type LandWithActions = LandWithMeta & {
  wait(): Promise<void>;
  increaseStake(amount: CurrencyAmount): TransactionResult;
  increasePrice(amount: CurrencyAmount): TransactionResult;
  claim(): TransactionResult;
  getPendingTaxes(): Promise<PendingTax[] | undefined>;
  getNextClaim(): Promise<NextClaimInformation[] | undefined>;
  getNukable(): Promise<number | undefined>;
  getCurrentAuctionPrice(): Promise<CurrencyAmount | undefined>;
  getYieldInfo(): Promise<LandYieldInfo | undefined>;
  getEstimatedNukeTime(): number | undefined;
  getNeighbors(): Neighbors;
  levelUp(): TransactionResult;
  getLevelInfo(): LevelInfo;
};

export abstract class BaseLand {
  protected readonly _type: LandType;
  public readonly location: Location;
  public readonly locationString: string;
  protected _owner: string = '';
  protected _boughtAt: Date = new Date(0);
  protected _sellPrice: CurrencyAmount;
  protected _token: Token;
  protected _level: Level;
  protected _stakeAmount: CurrencyAmount;
  protected _lastPayTime: Date = new Date(0);
  protected _block_date_bought: BigNumberish = 0;
  protected _sell_price: BigNumberish = 0;
  protected _token_used: string = '';

  constructor(type: LandType, location: Location, token: Token) {
    this._type = type;
    this.location = location;
    // Ensure location coordinates are valid numbers
    if (
      typeof location.x !== 'number' ||
      typeof location.y !== 'number' ||
      isNaN(location.x) ||
      isNaN(location.y)
    ) {
      console.error('Invalid location coordinates:', location);
      throw new Error('Invalid location coordinates');
    }

    this.locationString = toHexWithPadding(coordinatesToLocation(location));
    this._token = token;
    this._sellPrice = CurrencyAmount.fromUnscaled(0, token);
    this._stakeAmount = CurrencyAmount.fromUnscaled(0, token);
    const defaultLevel = {
      variant: 'First',
      unwrap: () => ({}),
      activeVariant: 'First',
    } as unknown as CairoCustomEnum;
    this._level = fromDojoLevel(defaultLevel);
  }

  get type() {
    return this._type;
  }

  // Common accessors
  public get owner(): string {
    return this._owner;
  }

  public get level(): Level {
    return this._level;
  }

  public get boughtAt(): Date {
    return this._boughtAt;
  }

  public get sellPrice(): CurrencyAmount {
    return this._sellPrice;
  }

  public get token(): Token {
    return this._token;
  }

  public get stakeAmount(): CurrencyAmount {
    return this._stakeAmount;
  }

  public get lastPayTime(): Date {
    return this._lastPayTime;
  }

  public get block_date_bought(): BigNumberish {
    return this._block_date_bought;
  }

  public get sell_price(): BigNumberish {
    return this._sell_price;
  }

  public get token_used(): string {
    return this._token_used;
  }

  public get tokenUsed(): string {
    return this._token_used;
  }

  public get tokenAddress(): string {
    return this._token.address;
  }

  // You should always be able to get the neighbors of a land
  public getNeighbors(store: LandTileStore): Neighbors {
    return Neighbors.getWithStoreAndLocation(this.locationString, store);
  }
}

export class EmptyLand extends BaseLand {
  constructor(location: Location) {
    super('empty', location, getTokenInfo('0x0')!);
  }

  static is(land: BaseLand): land is EmptyLand {
    return land.type === 'empty';
  }
}
