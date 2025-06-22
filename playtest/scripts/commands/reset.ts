import { file } from "bun";
import { Configuration } from "../env";
import {
  connect,
  doTransaction,
  getContractAddress,
  setAccess,
  Token,
} from "../utils";
import {
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  CallData,
} from "starknet";

export async function reset(config: Configuration, args: string[]) {
  console.log("Setting up wallet...");

  await connect(config);

  // Get the tokens
  const data = await file(
    `${config.basePath}/tokens.${config.environment}.json`,
  ).json();

  const socialinkAddress = data.socialinkAccount;
  const granterAddress = data.tokenGranterAddress;

  const calls = [
    {
      contractAddress: granterAddress,
      entrypoint: "set_mint_status",
      calldata: CallData.compile({
        address: args[0],
        status: new CairoOption<CairoCustomEnum>(CairoOptionVariant.None),
      }),
    },
  ];

  await doTransaction(calls);
}
