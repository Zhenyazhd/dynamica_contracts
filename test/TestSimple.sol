// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/src/Test.sol";
import {console} from "forge-std/src/console.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockToken} from "./MockToken.sol";
import {LMSRMarketMaker} from "../src/LMSRMarketMaker.sol";
import {MarketMakerFactory} from "../src/MarketMakerFactory.sol";
import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";

contract LMSRMarketMakerSimpleTest is Test {
    LMSRMarketMaker public marketMaker;
    MockToken public mockToken;
    int256 public constant UNIT_DEC = 1e18;
    int256 public constant alha = 3 * UNIT_DEC / 100;
    int256 ln_2 = ln(sd(2 * UNIT_DEC)).unwrap();
    address OWNER = address(0xABCD);
    address ORACLE = address(0x1234);
    address trader_0 = address(0);
    address trader_1 = address(1);
    address trader_2 = address(2);
    address trader_3 = address(3);

    function setUp() public {
        vm.startPrank(OWNER); // vm.prank(OWNER);
        mockToken = new MockToken();
        marketMaker = new LMSRMarketMaker(mockToken, 0);
        mockToken.mint(OWNER, 1_000_000 * 10 ** 18);
        mockToken.mint(trader_0, 1_000_000 * 10 ** 18);
        mockToken.mint(trader_1, 1_000_000 * 10 ** 18);
        mockToken.mint(trader_2, 1_000_000 * 10 ** 18);
        mockToken.mint(trader_3, 1_000_000 * 10 ** 18);
        uint256 startLiquidity = 10 * 10 ** 18;
        mockToken.approve(address(marketMaker), startLiquidity);
        string memory question = "eth/usdc";
        int256 qAmounts = 1_000e18; //int(startLiquidity) * UNIT_DEC/(UNIT_DEC+2*ln_2);
        marketMaker.prepareCondition(ORACLE, question, 5);
        marketMaker.initializeMarket(startLiquidity, uint256(qAmounts));
        vm.stopPrank();
        // vm.writeLine("gas_data_fuzzed_hard.csv", "gas_used");
    }

    function testAllCicleSimple() public {
        address[] memory traders = new address[](21);
        traders[0] = trader_0;
        traders[1] = trader_1;
        traders[2] = trader_2;
        traders[3] = trader_3;
        traders[4] = trader_0;
        traders[5] = trader_1;
        traders[6] = trader_2;
        traders[7] = trader_3;
        traders[8] = trader_2;
        traders[9] = trader_3;
        traders[10] = trader_1;
        traders[11] = trader_2;
        traders[12] = trader_3;
        traders[13] = trader_2;
        traders[14] = trader_3;
        traders[15] = trader_1;
        traders[16] = trader_2;
        traders[17] = trader_3;
        traders[18] = trader_2;
        traders[19] = trader_3;
        traders[20] = trader_1;

        uint8[] memory buy_ids = new uint8[](21);
        buy_ids[0] = 4;
        buy_ids[1] = 0;
        buy_ids[2] = 1;
        buy_ids[3] = 4;
        buy_ids[4] = 0;
        buy_ids[5] = 0;
        buy_ids[6] = 1;
        buy_ids[7] = 0;
        buy_ids[8] = 1;
        buy_ids[9] = 4;
        buy_ids[10] = 0;
        buy_ids[11] = 1;
        buy_ids[12] = 0;
        buy_ids[13] = 1;
        buy_ids[14] = 4;
        buy_ids[15] = 0;
        buy_ids[16] = 1;
        buy_ids[17] = 0;
        buy_ids[18] = 1;
        buy_ids[19] = 4;
        buy_ids[20] = 0;

        int256[] memory amounts = new int256[](21);
        amounts[0] = 45e18;
        amounts[1] = 37e18;
        amounts[2] = 41e18;
        amounts[3] = 94e18;
        amounts[4] = 23e18;
        amounts[5] = 23e18;
        amounts[6] = 47e18;
        amounts[7] = 15e18;
        amounts[8] = 4e18;
        amounts[9] = 37e18;
        amounts[10] = 14e18;
        amounts[11] = 20e18;
        amounts[12] = 9e18;
        amounts[13] = 3e18;
        amounts[14] = 17e18;
        amounts[15] = 6e18;
        amounts[16] = 9e18;
        amounts[17] = 6e18;
        amounts[18] = 2e18;
        amounts[19] = 9e18;
        amounts[20] = 1e18;
        assertEq(traders.length, buy_ids.length);
        assertEq(traders.length, amounts.length);
        int256[] memory deltaOutcomeAmounts_ = new int256[](5);
        uint256 startGas = 0;
        uint256 used = 0;
        for (uint256 i = 0; i < traders.length; i++) {
            vm.startPrank(traders[i]);
            for (uint256 j = 0; j < 5; j++) {
                if (j == buy_ids[i]) {
                    deltaOutcomeAmounts_[j] = amounts[i];
                } else {
                    deltaOutcomeAmounts_[j] = 0;
                }
            }
            mockToken.approve(address(marketMaker), 40e18);

            startGas = gasleft();
            marketMaker.makePrediction(deltaOutcomeAmounts_);
            used = startGas - gasleft();
            string memory line = vm.toString(used);
            //vm.writeLine("gas_data_fuzzed.csv", line);
            vm.stopPrank();
        }
    }

    function testAllCicleComplex() public {
        address[] memory traders = new address[](11);
        traders[0] = trader_0;
        traders[1] = trader_1;
        traders[2] = trader_2;
        traders[3] = trader_3;
        traders[4] = trader_0;
        traders[5] = trader_1;
        traders[6] = trader_2;
        traders[7] = trader_3;
        traders[8] = trader_2;
        traders[9] = trader_3;
        traders[10] = trader_1;

        int256[][] memory amounts = new int256[][](11);

        amounts[0] = new int256[](5);
        amounts[0][0] = 546e18;
        amounts[0][1] = 514e18;
        amounts[0][2] = 224e18;
        amounts[0][3] = 458e18;
        amounts[0][4] = 626e18;
        amounts[1] = new int256[](5);
        amounts[1][0] = 527e18;
        amounts[1][1] = 496e18;
        amounts[1][2] = 224e18;
        amounts[1][3] = 458e18;
        amounts[1][4] = 505e18;
        amounts[2] = new int256[](5);
        amounts[2][0] = 299e18;
        amounts[2][1] = 136e18;
        amounts[2][2] = 224e18;
        amounts[2][3] = 458e18;
        amounts[2][4] = 286e18;
        amounts[3] = new int256[](5);
        amounts[3][0] = 263e18;
        amounts[3][1] = 136e18;
        amounts[3][2] = 183e18;
        amounts[3][3] = 418e18;
        amounts[3][4] = 286e18;
        amounts[4] = new int256[](5);
        amounts[4][0] = 143e18;
        amounts[4][1] = 136e18;
        amounts[4][2] = 181e18;
        amounts[4][3] = 179e18;
        amounts[4][4] = 167e18;
        amounts[5] = new int256[](5);
        amounts[5][0] = 92e18;
        amounts[5][1] = 122e18;
        amounts[5][2] = 121e18;
        amounts[5][3] = 179e18;
        amounts[5][4] = 118e18;
        amounts[6] = new int256[](5);
        amounts[6][0] = 53e18;
        amounts[6][1] = 88e18;
        amounts[6][2] = 85e18;
        amounts[6][3] = 68e18;
        amounts[6][4] = 117e18;
        amounts[7] = new int256[](5);
        amounts[7][0] = 53e18;
        amounts[7][1] = 62e18;
        amounts[7][2] = 65e18;
        amounts[7][3] = 68e18;
        amounts[7][4] = 66e18;
        amounts[8] = new int256[](5);
        amounts[8][0] = 0;
        amounts[8][1] = 11e18;
        amounts[8][2] = 25e18;
        amounts[8][3] = 68e18;
        amounts[8][4] = 28e18;
        amounts[9] = new int256[](5);
        amounts[9][0] = 0;
        amounts[9][1] = 10e18;
        amounts[9][2] = 9e18;
        amounts[9][3] = 0;
        amounts[9][4] = 21e18;
        amounts[10] = new int256[](5);
        amounts[10][0] = 0;
        amounts[10][1] = 2e18;
        amounts[10][2] = 2e18;
        amounts[10][3] = 0;
        amounts[10][4] = 1e18;

        int256[] memory deltaOutcomeAmounts_ = new int256[](5);
        uint256 startGas = 0;
        uint256 used = 0;
        for (uint256 i = 0; i < traders.length; i++) {
            vm.startPrank(traders[i]);
            mockToken.approve(address(marketMaker), 1_000e18);
            startGas = gasleft();
            marketMaker.makePrediction(amounts[i]);
            used = startGas - gasleft();
            //string memory line = vm.toString(used);
            //vm.writeLine("gas_data_fuzzed_hard.csv", line);
            vm.stopPrank();
        }
    }

    function testReportPayoutComplex() public {
        uint256 startBalance_0 = mockToken.balanceOf(address(trader_0));
        uint256 startBalance_1 = mockToken.balanceOf(address(trader_1));
        uint256 startBalance_2 = mockToken.balanceOf(address(trader_2));
        uint256 startBalance_3 = mockToken.balanceOf(address(trader_3));
        testAllCicleComplex();
        uint256[] memory payouts = new uint256[](5);
        payouts[0] = 25 * uint256(UNIT_DEC) / 100;
        payouts[1] = 25 * uint256(UNIT_DEC) / 100;
        payouts[2] = 10 * uint256(UNIT_DEC) / 100;
        payouts[3] = 10 * uint256(UNIT_DEC) / 100;
        payouts[4] = 30 * uint256(UNIT_DEC) / 100;
        vm.prank(ORACLE);
        marketMaker.closeMarket(payouts);

        vm.prank(trader_0);
        marketMaker.redeemPayout();

        vm.prank(trader_1);
        marketMaker.redeemPayout();

        vm.prank(trader_2);
        marketMaker.redeemPayout();

        vm.prank(trader_3);
        marketMaker.redeemPayout();

        uint256 endBalance_0 = mockToken.balanceOf(address(trader_0));
        uint256 endBalance_1 = mockToken.balanceOf(address(trader_1));
        uint256 endBalance_2 = mockToken.balanceOf(address(trader_2));
        uint256 endBalance_3 = mockToken.balanceOf(address(trader_3));

        console.log("before_0 > after_0", startBalance_0 > endBalance_0);
        console.log(startBalance_0 - endBalance_0);
        console.log("before_1 > after_1", startBalance_1 > endBalance_1);
        console.log(startBalance_1 - endBalance_1);
        console.log("before_2 > after_2", startBalance_2 > endBalance_2);
        console.log(startBalance_2 - endBalance_2);
        console.log("before_3 > after_3", startBalance_3 > endBalance_3);
        console.log(startBalance_3 - endBalance_3);
    }

    function testReportPayoutSimple() public {
        uint256 startBalance_0 = mockToken.balanceOf(address(trader_0));
        uint256 startBalance_1 = mockToken.balanceOf(address(trader_1));
        uint256 startBalance_2 = mockToken.balanceOf(address(trader_2));
        uint256 startBalance_3 = mockToken.balanceOf(address(trader_3));
        testAllCicleSimple();

        uint256 middleBalance_0 = mockToken.balanceOf(address(trader_0));
        uint256 middleBalance_1 = mockToken.balanceOf(address(trader_1));
        uint256 middleBalance_2 = mockToken.balanceOf(address(trader_2));
        uint256 middleBalance_3 = mockToken.balanceOf(address(trader_3));
        uint256[] memory payouts = new uint256[](5);
        payouts[0] = 25 * uint256(UNIT_DEC) / 100;
        payouts[1] = 25 * uint256(UNIT_DEC) / 100;
        payouts[2] = 10 * uint256(UNIT_DEC) / 100;
        payouts[3] = 10 * uint256(UNIT_DEC) / 100;
        payouts[4] = 30 * uint256(UNIT_DEC) / 100;
        vm.prank(ORACLE);
        marketMaker.closeMarket(payouts);

        vm.prank(trader_0);
        marketMaker.redeemPayout();

        vm.prank(trader_1);
        marketMaker.redeemPayout();

        vm.prank(trader_2);
        marketMaker.redeemPayout();

        vm.prank(trader_3);
        marketMaker.redeemPayout();

        uint256 endBalance_0 = mockToken.balanceOf(address(trader_0));
        uint256 endBalance_1 = mockToken.balanceOf(address(trader_1));
        uint256 endBalance_2 = mockToken.balanceOf(address(trader_2));
        uint256 endBalance_3 = mockToken.balanceOf(address(trader_3));

        console.log("middle_0 < before_0", middleBalance_0 < startBalance_0);
        console.log(startBalance_0 - middleBalance_0);
        console.log("middle_1 < before_1", middleBalance_1 < startBalance_1);
        console.log(startBalance_1 - middleBalance_1);
        console.log("middle_2 < before_2", middleBalance_2 < startBalance_2);
        console.log(startBalance_2 - middleBalance_2);
        console.log("middle_3 < before_3", middleBalance_3 < startBalance_3);
        console.log(startBalance_3 - middleBalance_3);

        console.log("before_0 > after_0", startBalance_0 > endBalance_0);
        console.log(endBalance_0 - startBalance_0);
        console.log("before_1 > after_1", startBalance_1 > endBalance_1);
        console.log(startBalance_1 - endBalance_1);
        console.log("before_2 > after_2", startBalance_2 > endBalance_2);
        console.log(startBalance_2 - endBalance_2);
        console.log("before_3 > after_3", startBalance_3 > endBalance_3);
        console.log(startBalance_3 - endBalance_3);
    }

    function testSellComplex() public {
        address[] memory traders = new address[](3);
        traders[0] = trader_1;
        traders[1] = trader_1;
        traders[2] = trader_1;

        int256[][] memory amounts = new int256[][](3);

        amounts[0] = new int256[](5);
        amounts[0][0] = 546e18;
        amounts[0][1] = 514e18;
        amounts[0][2] = 224e18;
        amounts[0][3] = 458e18;
        amounts[0][4] = 626e18;
        amounts[1] = new int256[](5);
        amounts[1][0] = 527e18;
        amounts[1][1] = 496e18;
        amounts[1][2] = 224e18;
        amounts[1][3] = 458e18;
        amounts[1][4] = 505e18;
        amounts[2] = new int256[](5);
        amounts[2][0] = -527e18;
        amounts[2][1] = -496e18;
        amounts[2][2] = -224e18;
        amounts[2][3] = -458e18;
        amounts[2][4] = -505e18;

        int256[] memory deltaOutcomeAmounts_ = new int256[](5);
        uint256 startGas = 0;
        uint256 used = 0;

        vm.startPrank(trader_0);
        mockToken.approve(address(marketMaker), 1_000_000e18);

        uint256 balance_0 = mockToken.balanceOf(address(trader_0));
        marketMaker.makePrediction(amounts[0]);

        uint256 balance_1 = mockToken.balanceOf(address(trader_0));
        marketMaker.makePrediction(amounts[1]);

        uint256 balance_2 = mockToken.balanceOf(address(trader_0));
        marketMaker.makePrediction(amounts[2]);

        uint256 balance_3 = mockToken.balanceOf(address(trader_0));

        console.log("balance_0", balance_0);
        console.log("balance_1", balance_1);
        console.log("balance_2", balance_2);
        console.log("balance_3", balance_3);

        vm.stopPrank();
    }

    /*
    * ============================================================================
    *                    RESEARCH STABILITY ANALYSIS SECTION
    * ============================================================================
    *
    * This section contains comprehensive gas consumption analysis tests for the
    * LMSR (Logarithmic Market Scoring Rule) market maker formula stability research.
    *
    * Purpose: These tests were designed to analyze the gas efficiency and computational
    * stability of the LMSR formula under various market conditions and parameter ranges.
    * The research focused on understanding how gas consumption varies with different
    * input parameters and market states, ensuring the formula remains efficient and
    * predictable across all possible scenarios.
    *
    * Key Research Areas:
    * - Gas consumption patterns with varying delta values
    * - Computational stability under extreme market conditions
    * - Performance analysis across different parameter ranges
    * - Formula behavior validation under stress conditions
    *
    * While the improvements in the code it was not really possible to keep the tests
    * up to date, so at this stage they are not running
    *
    * ============================================================================
    */

    /*  // Helper function for generating random numbers with fixed precision
    // Uses UNIT_DEC from the contract for scaling
    function _generateFixedPoint(uint seed, uint maxFloatValue) internal view returns (int) {
        // Multiply by the contract's UNIT_DEC to get a fixed-point number
        // For simplicity, generate a number from 0 to maxFloatValue * UNIT_DEC
        // Use modulo to get a value in the range [0, scaledMax]
        // Then convert to int
        return int(seed % (maxFloatValue + 1));
    }

    // Helper function for writing to CSV
    function _logGasAndResult(int[] memory deltas, int[] memory bals, int result, uint usedGas) internal {
        string memory line = string.concat(
            vm.toString(deltas[0]), ",",
            vm.toString(deltas[1]), ",",
            vm.toString(bals[0]),   ",",
            vm.toString(bals[1]),   ",",
            vm.toString(result),",",
            vm.toString(usedGas)
        );
        vm.writeLine("gas_data_fuzzed_3.csv", line);
    }


    function testFuzz_calcNetCost_fuzzed(
        int256[10] memory deltas
    ) public {
        int256[] memory bals = new int256[](deltas.length);
        int256[] memory deltas_ = new int256[](deltas.length);

        for(uint i = 0; i < deltas.length; i++) {
            deltas_[i] = bound(deltas[i], 10e9, 10e25);
            bals[i]   = bound(int256(uint256(keccak256(abi.encode(deltas[i], i)))), 10e9, 10e25);
        }

        // 3) Call the function
        uint startGas = gasleft();
        int256 result = marketMaker.calcNetCost(deltas_, bals);
        uint used    = startGas - gasleft();

        // 4) Log the results — you can still collect CSV data
        _logGasAndResult(deltas_, bals, result, used);

        // 5) (Optional) Some assertions
        // assertGe(result, 0);
    }

    function testFuzz_calcNetCost_fuzzed(
        int256[] memory deltas,
        int256[] memory bals
    ) public {
        vm.assume( deltas.length == bals.length && deltas.length <= 10 && deltas.length > 1);
        //vm.assume(deltas.length == bals.length);
        for(uint i = 0; i < deltas.length; i++) {
            deltas[i] = bound(deltas[i], 10e9, 10e25);
            bals[i] = bound(bals[i], 10e9, 10e25);
        }

        // 3) Call the function
        uint startGas = gasleft();
        int256 result = marketMaker.calcNetCost(deltas, bals);
        uint used    = startGas - gasleft();

        // 4) Log the results — you can still collect CSV data
        _logGasAndResult(deltas, bals, result, used);

        // 5) (Optional) Some assertions
        // assertGe(result, 0);
    }*/

    /*function testFuzz_calcNetCost_fuzzed(
        int256 delta0_,
        int256 delta1_,
        int256 bal0_,
        int256 bal1_
    ) public {
        int delta0 = bound(delta0_, 10e9, 10e25);  // now 0 ≤ delta0 ≤ 10e18
        int delta1 = bound(delta1_, 10e9, 10e25);
        int bal0   = bound(bal0_,   10e9, 10e25);
        int bal1   = bound(bal1_,   10e9, 10e25);

        // 2) Pack into arrays
        int256[] memory deltas = new int256[](2);
        deltas[0] = delta0; deltas[1] = delta1;
        int256[] memory bals = new int256[](2);
        bals[0]   = bal0;   bals[1]   = bal1;

        // 3) Call the function
        uint startGas = gasleft();
        int256 result = marketMaker.calcNetCost(deltas, bals);
        uint used    = startGas - gasleft();

        // 4) Log the results — you can still collect CSV data
        _logGasAndResult(deltas, bals, result, used);

        // 5) (Optional) Some assertions
        // assertGe(result, 0);
    }*/

    // --- Original test adapted for general functions ---
    /* function test_collectGasAndResult_RandomGeneral() public {
        // Add header if file doesn't exist yet or we want to rewrite it
        // This can be done in setUp, but for more flexibility we'll leave it here.
        // vm.writeLine("gas_data.csv", "q0,q1,balances0,balances1,resultCost,gas_used");
        // It's best to do this once in setUp to avoid duplicating headers
        // if many tests are run.
        vm.startBroadcast(); // For executing operations on the contract

        // Initialize file with header only once, on first test run.
        // If you run tests one by one, it's better to add this to setUp
        // and ensure the file is cleared between full runs.
        // For demonstration, I'll leave it here, but keep in mind.
        vm.writeLine("gas_data.csv", "delta0,delta1,bal0,bal1,resultCost,gas_used");

        for (uint i = 1; i <= 100; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i)));

            // Generate deltas and balances in fixed point using UNIT_DEC
            // Maximum "floating" value for generation
            uint maxFloatDelta = 10; // For example, deltas up to 10 tokens
            uint maxFloatBal = 100;  // Balances up to 100 tokens (if they are used in calcNetCost)

            int delta0 = _generateFixedPoint(seed, maxFloatDelta);
            int delta1 = _generateFixedPoint(seed >> 3, maxFloatDelta);
            int bal0   = _generateFixedPoint(seed >> 5, maxFloatBal);
            int bal1   = _generateFixedPoint(seed >> 7, maxFloatBal);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0]   = bal0;   bals[1]   = bal1;
            console.log(bals[0]);
            console.log(bals[1]);
            uint startGas = gasleft();
            int result    = marketMaker.calcNetCost(deltas, bals); // Assuming calcNetCost exists
            uint used     = startGas - gasleft();

            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // --- Various testing scenarios ---

    // 1. Test with very small deltas (close to zero)
    function test_collectGasAndResult_SmallDeltas() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 1000))); // Different seed
            int delta0 = _generateFixedPoint(seed, 1 * uint(marketMaker.UNIT_DEC()) / 1000); // Very small deltas
            int delta1 = _generateFixedPoint(seed >> 3, 1 * uint(marketMaker.UNIT_DEC()) / 1000);
            int bal0   = _generateFixedPoint(seed >> 5, 50); // Medium balances
            int bal1   = _generateFixedPoint(seed >> 7, 50);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;
            console.log(bals[0]);
            console.log(bals[1]);

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 2. Test with very large deltas (potentially causing significant price changes)
    function test_collectGasAndResult_LargeDeltas() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 2000)));
            int delta0 = _generateFixedPoint(seed, 100); // Large deltas
            int delta1 = _generateFixedPoint(seed >> 3, 100);
            int bal0   = _generateFixedPoint(seed >> 5, 10);
            int bal1   = _generateFixedPoint(seed >> 7, 10);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;
            console.log(bals[0]);
            console.log(bals[1]);
            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 3. Test with one zero delta (buying only one outcome)
    function test_collectGasAndResult_OneZeroDelta() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 3000)));
            int delta0 = _generateFixedPoint(seed, 5);
            int delta1 = 0; // One delta equals zero
            int bal0   = _generateFixedPoint(seed >> 5, 20);
            int bal1   = _generateFixedPoint(seed >> 7, 20);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;
            console.log(bals[0]);
            console.log(bals[1]);
            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 4. Test where deltas differ greatly in magnitude (e.g., 0.1 and 100)
    function test_collectGasAndResult_MixedDeltas() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 4000)));
            int delta0 = _generateFixedPoint(seed, 1 * uint(marketMaker.UNIT_DEC()) / 10);
            int delta1 = _generateFixedPoint(seed >> 3, 100); // Strong difference
            int bal0   = _generateFixedPoint(seed >> 5, 30);
            int bal1   = _generateFixedPoint(seed >> 7, 30);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 5. Test with varying initial market state (q0) -
    // This test will reset the contract state in each cycle,
    // which may be more resource-intensive and may lead to "flooding" in CSV,
    // but allows studying behavior at different initial q values.
    // If marketMaker is not 'public', you may need to move
    // marketMaker creation inside the loop or use a helper function.
    function test_collectGasAndResult_VaryingInitialQ() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 20; i++) { // Fewer iterations due to reset
            uint seed = uint(keccak256(abi.encodePacked(i + 5000)));
            // Reset contract for new initial q
            // This implies your contract has a 'reset' function or you recreate it.
            // marketMaker = new YourMarketMakerContract(500, 2, [_generateFixedPoint(seed, 100), _generateFixedPoint(seed >> 1, 100)]);
            // More realistic approach: just trade from initial Q, but make changes to q0 before each scenario.
            // However, calcNetCost doesn't take q0 as an input parameter.
            // For this purpose, it's best to use 'vm.roll(block.number + i);' to change network state
            // or directly manipulate storage (for more advanced tests).
            // For simplicity, this test may be less useful without a state reset function.

            // Instead of changing q0, we can just continue trading and
            // see how gas behaves with heavily modified q values.
            // For this scenario, we just continue trading using the current q state
            // (which will change from iteration to iteration).

            // Use relatively small deltas to avoid heavily distorting q
            int delta0 = _generateFixedPoint(seed >> 2, 5);
            int delta1 = _generateFixedPoint(seed >> 4, 5);
            int bal0   = _generateFixedPoint(seed >> 6, 50);
            int bal1   = _generateFixedPoint(seed >> 8, 50);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 6. Test where balances are very large (if they are used in calculations)
    function test_collectGasAndResult_LargeBalances() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 6000)));
            int delta0 = _generateFixedPoint(seed, 5);
            int delta1 = _generateFixedPoint(seed >> 3, 5);
            int bal0   = _generateFixedPoint(seed >> 5, 1e6); // Very large balances
            int bal1   = _generateFixedPoint(seed >> 7, 1e6);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 7. Test where balances are very small or close to zero
    function test_collectGasAndResult_SmallBalances() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 7000)));
            int delta0 = _generateFixedPoint(seed, 5);
            int delta1 = _generateFixedPoint(seed >> 3, 5);
            int bal0   = _generateFixedPoint(seed >> 5, 1 * uint(marketMaker.UNIT_DEC()) / 100); // Small balances
            int bal1   = _generateFixedPoint(seed >> 7, 1 * uint(marketMaker.UNIT_DEC()) / 100);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 8. Test with negative deltas (if your contract handles them for "selling")
    // In the current code `assert np.all(dq >= 0)` in Python,
    // and `assert all(dq >= 0 for dq in delta_q_wad)` in the FixedPoint version.
    // If `calcNetCost` in Solidity can accept negative deltas (for selling),
    // you need to modify the `assert` in the Solidity contract accordingly.
    // If not, this test will fail on `assert`.
    function test_collectGasAndResult_NegativeDeltas() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 8000)));
            int delta0 = -_generateFixedPoint(seed, 5); // Negative deltas
            int delta1 = -_generateFixedPoint(seed >> 3, 5);
            int bal0   = _generateFixedPoint(seed >> 5, 50);
            int bal1   = _generateFixedPoint(seed >> 7, 50);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;

            // This test will cause an error if your contract doesn't support negative deltas.
            // Update `calcNetCost` or `trade` in `YourMarketMakerContract.sol`
            // to handle negative deltas if necessary.
            // For example, marketMaker.trade(deltas) instead of calcNetCost,
            // if trade can accept negative values.
            uint startGas = gasleft();
            // vm.expectRevert(); // Expect revert if negative deltas are not supported
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 9. Тест, где MarketMaker находится в "экстремальном" состоянии (очень сильно смещенные q)
    // Для этого нужно сначала сильно изменить q в контракте.
    function test_collectGasAndResult_ExtremeQ() public {
        vm.startBroadcast();
        // Сначала "проторгуем" много, чтобы сильно сместить q
        int[] memory deltas = new int[](2);
        deltas[0] = int(100 * marketMaker.UNIT_DEC());
        deltas[1] = 0;
        int[] memory bals = new int[](2);
        bals[0] = 0;
        bals[1] = 0;
        marketMaker.calcNetCost(deltas, bals);
        deltas[0] = int(50 * marketMaker.UNIT_DEC());
        deltas[1] = 0;
        marketMaker.calcNetCost(deltas, bals);
        deltas[0] = 0;
        deltas[1] = int(200 * marketMaker.UNIT_DEC());
        marketMaker.calcNetCost(deltas, bals);

        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 9000)));
            int delta0 = _generateFixedPoint(seed, 1);
            int delta1 = _generateFixedPoint(seed >> 3, 1);
            int bal0   = _generateFixedPoint(seed >> 5, 10);
            int bal1   = _generateFixedPoint(seed >> 7, 10);

            deltas[0] = delta0; deltas[1] = delta1;
            bals[0] = bal0; bals[1] = bal1;

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }

    // 10. Тест с нулем в одном из балансов (если это имеет значение для вашей логики)
    function test_collectGasAndResult_ZeroBalance() public {
        vm.startBroadcast();
        for (uint i = 1; i <= 50; i++) {
            uint seed = uint(keccak256(abi.encodePacked(i + 10000)));
            int delta0 = _generateFixedPoint(seed, 5);
            int delta1 = _generateFixedPoint(seed >> 3, 5);
            int bal0   = 0; // Один из балансов равен нулю
            int bal1   = _generateFixedPoint(seed >> 7, 50);

            int[] memory deltas = new int[](2);
            deltas[0] = delta0; deltas[1] = delta1;
            int[] memory bals = new int[](2);
            bals[0] = bal0; bals[1] = bal1;

            uint startGas = gasleft();
            int result = marketMaker.calcNetCost(deltas, bals);
            uint used = startGas - gasleft();
            _logGasAndResult(deltas, bals, result, used);
        }
        vm.stopBroadcast();
    }*/
}
