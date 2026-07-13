// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";

import { AstralCreditMarket } from "../src/AstralCreditMarket.sol";
import { AstralRateModel } from "../src/interest/AstralRateModel.sol";
import { AstralOracleRouter } from "../src/oracle/AstralOracleRouter.sol";
import { AstralRiskEngine } from "../src/risk/AstralRiskEngine.sol";

contract DeployAstral is Script {
    uint256 internal constant RAY = 1e27;

    function run()
        external
        returns (
            AstralCreditMarket market,
            AstralOracleRouter oracle,
            AstralRateModel rateModel,
            AstralRiskEngine riskEngine
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerKey);
        address treasury = vm.envAddress("ASTRAL_TREASURY");

        vm.startBroadcast(deployerKey);
        oracle = new AstralOracleRouter(admin);
        rateModel = new AstralRateModel(8e26, 2e25, 5e25, 8e26);
        market = new AstralCreditMarket(admin, treasury);
        riskEngine = new AstralRiskEngine(market);
        market.setRiskEngine(address(riskEngine));
        vm.stopBroadcast();
    }
}
