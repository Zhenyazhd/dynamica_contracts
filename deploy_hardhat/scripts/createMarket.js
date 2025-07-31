const { ethers } = require("hardhat");
const config = require("./marketMaker.config");
const DynamicaFactoryJson = require("../../out/MarketMakerFactory.sol/DynamicaFactory.json");
const ChainlinkResolutionModuleJson = require("../../out/ChainlinkResolutionModule.sol/ChainlinkResolutionModule.json");
const IHederaTokenServiceJson = require("../../out/IHederaTokenService.sol/IHederaTokenService.json");

async function main() {
    const provider = ethers.provider;      
    const wallet   = new ethers.Wallet(config.deployerKey, provider);

    console.log("Deploying with:", wallet.address);

    const factory = await ethers.getContractAt(
        DynamicaFactoryJson.abi,
        config.implementations.factory,
        wallet
    );

   /* const ChainlinkResolution = await ethers.getContractFactory(
        ChainlinkResolutionModuleJson.abi,
        wallet
    );*/

    const chainlinkConfig = {
        priceFeedAddresses: [config.oracles.ethUsd, config.oracles.btcUsd],
        staleness:          [3600, 3600],
        decimals:           [8, 8]
    };

    // Формируем массив токенов HTS
    /*const IHederaToken = IHederaTokenServiceJson.abi.HederaToken;
    console.log(IHederaToken);
    const tokens = [];
    for (let i = 0; i < config.marketParams.outcomeSlotCount; i++) {
        tokens.push(IHederaToken.from({
        name:   `testToken${i}`,
        symbol: `test${i}`,
        treasury: config.owner,
        expiry: {
            second:            0,
            autoRenewAccount:  config.owner,
            autoRenewPeriod:   5184000
        },
        // остальные поля по-умолчанию
        }));
    }*/

    const tokens = [];
    for (let i = 0; i < config.marketParams.outcomeSlotCount; i++) {
    tokens.push(
        {
            name:            `testToken${i}`,
            symbol:          `test${i}`,
            treasury:        config.owner,
            memo:            "",
            tokenSupplyType: false,
            maxSupply:       0,
            freezeDefault:   false,
            tokenKeys:       [],
            expiry: {
            second:            0,
            autoRenewAccount:  config.owner,
            autoRenewPeriod:   5184000
            }
        });
    }


  // Вызываем создание рынка
    const tx = await factory.createMarketMaker(
        {
        owner:               config.owner,
        collateralToken:     config.collateralToken,
        oracle:              config.owner,
        question:            config.marketParams.question,
        outcomeSlotCount:    config.marketParams.outcomeSlotCount,
        startFunding:        config.marketParams.startFunding,
        outcomeTokenAmounts: config.marketParams.outcomeTokenAmounts,
        fee:                 config.marketParams.fee,
        alpha:               config.marketParams.alpha,
        expLimit:            config.marketParams.expLimit,
        decimals:            config.marketParams.decimals
        },
        {
        marketMaker:        '0x0000000000000000000000000000000000000000',
        outcomeSlotCount:   config.marketParams.outcomeSlotCount,
        resolutionModule:   '0x0000000000000000000000000000000000000000',
        resolutionData:     '0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000004563918244f40000',
        isResolved:        false,
        expirationTime:    config.marketParams.expirationTime,
        resolutionModuleType:
            0 // IMarketResolutionModule.ResolutionModule.CHAINLINK
        },
        tokens,
        { value: ethers.parseEther("40") }
    );
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("Market created at:", (await factory.marketMakers(0)));
}

main().catch(console.error);

/**
 * npx hardhat run \
  scripts/createMarket.js \
  --network testnet
 */