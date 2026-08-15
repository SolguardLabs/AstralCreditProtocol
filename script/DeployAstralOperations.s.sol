// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";

import { AstralTimelockQueue } from "../src/governance/AstralTimelockQueue.sol";
import { IAstralMarketView } from "../src/interfaces/IAstralMarketView.sol";
import { IAstralRiskEngine } from "../src/interfaces/IAstralRiskEngine.sol";
import { AstralAccountLens } from "../src/lens/AstralAccountLens.sol";
import { AstralCreditLens } from "../src/lens/AstralCreditLens.sol";
import { AstralMarketReporter } from "../src/lens/AstralMarketReporter.sol";
import { AstralPortfolioStress } from "../src/risk/AstralPortfolioStress.sol";
import { AstralCheckpointRegistry } from "../src/security/AstralCheckpointRegistry.sol";

contract DeployAstralOperations is Script {
    struct Deployment {
        AstralTimelockQueue timelock;
        AstralCheckpointRegistry checkpoints;
        AstralPortfolioStress stress;
        AstralCreditLens creditLens;
        AstralAccountLens accountLens;
        AstralMarketReporter reporter;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerKey);
        IAstralMarketView market = IAstralMarketView(vm.envAddress("ASTRAL_MARKET"));
        IAstralRiskEngine riskEngine = IAstralRiskEngine(vm.envAddress("ASTRAL_RISK_ENGINE"));
        uint40 delay = uint40(vm.envUint("ASTRAL_TIMELOCK_DELAY"));
        uint40 grace = uint40(vm.envUint("ASTRAL_TIMELOCK_GRACE"));
        uint16 quorum = uint16(vm.envUint("ASTRAL_CHECKPOINT_QUORUM"));

        vm.startBroadcast(deployerKey);
        deployment.timelock = new AstralTimelockQueue(admin, delay, grace);
        deployment.checkpoints = new AstralCheckpointRegistry(admin, quorum);
        deployment.stress = new AstralPortfolioStress();
        deployment.creditLens = new AstralCreditLens(market, riskEngine);
        deployment.accountLens = new AstralAccountLens(market, riskEngine);
        deployment.reporter = new AstralMarketReporter(market);
        vm.stopBroadcast();
    }
}
