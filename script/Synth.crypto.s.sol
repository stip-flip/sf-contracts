// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import '../src/SynthFactory.sol';
import '../src/interfaces/IOracleView.sol';
import './lib/Strings.sol';
import 'forge-std/Script.sol';

function addressToString(address a) pure returns (string memory) {
    return Strings.toHexString(uint(uint160(a)), 20);
}

contract SynthScript is Script {
    IOracleView cryptoOracle =
        IOracleView(
            vm.envAddress(
                string(
                    abi.encodePacked(
                        'CRYPTO_ORACLE_',
                        Strings.toString(block.chainid)
                    )
                )
            )
        );

    string path =
        string(
            abi.encodePacked(
                './addresses/',
                Strings.toString(block.chainid),
                '/synth'
            )
        );

    SynthFactory factory;

    function fillMarket(address pool) public {
        // Synth(pool).mint{value: 1 ether}(300, vm.envAddress('BOT_ADDRESS'));
        // Synth(pool).mint{value: 2 ether}(350, vm.envAddress('BOT_ADDRESS'));
        // Synth(pool).mint{value: 3 ether}(400, vm.envAddress('BOT_ADDRESS'));
        // Synth(pool).mint{value: 5 ether}(600, vm.envAddress('BOT_ADDRESS'));
    }

    function createSynth(
        uint8 slot,
        bool long,
        bool leveraged,
        string memory name,
        string memory description
    ) internal {
        address synth = factory.createSynth(
            cryptoOracle,
            slot,
            name,
            description,
            long,
            IOracleView.Leverage.NONE
        );

        vm.writeLine(
            path,
            string(abi.encodePacked(long ? 'Stip-' : 'Flip-', name, ': '))
        );
        vm.writeLine(path, addressToString(address(synth)));

        if (!leveraged) return;
        // create it again squared
        address synthSquared = factory.createSynth(
            cryptoOracle,
            slot,
            name,
            string(abi.encodePacked(description, ' Squared')),
            long,
            IOracleView.Leverage.SQUARED
        );

        vm.writeLine(
            path,
            string(abi.encodePacked(long ? 'Stip-' : 'Flip-', name, '^2: '))
        );
        vm.writeLine(path, addressToString(address(synthSquared)));

        // create it again cubed
        address synthCubed = factory.createSynth(
            cryptoOracle,
            slot,
            name,
            string(abi.encodePacked(description, ' Cubed')),
            long,
            IOracleView.Leverage.CUBED
        );

        vm.writeLine(
            path,
            string(abi.encodePacked(long ? 'Stip-' : 'Flip-', name, '^3: '))
        );
        vm.writeLine(path, addressToString(address(synthCubed)));
    }

    function run() public {
        vm.startBroadcast();
        // factory = SynthFactory(vm.envAddress('SYNTH_FACTORY'));
        factory = new SynthFactory();

        vm.writeLine(path, '--------------------------------------');
        vm.writeLine(path, 'SYNTH_FACTORY: ');
        vm.writeLine(path, addressToString(address(factory)));

        console.log('Oracle address: ', addressToString(address(cryptoOracle)));

        createSynth(0, true, false, 'USD', 'Synthetic USD');

        createSynth(1, true, true, 'BTC', 'Synthetic Bitcoin');

        createSynth(1, false, true, 'BTC', 'Flip Synthetic Bitcoin');

        createSynth(2, true, true, 'ETH', 'Synthetic Ether');

        createSynth(2, false, true, 'ETH', 'Flip Synthetic Ether');

        createSynth(3, true, true, 'DOGE', 'Synthetic Doge');

        createSynth(3, false, true, 'DOGE', 'Flip Synthetic Doge');

        createSynth(4, true, true, 'XMR', 'Synthetic Monero');

        createSynth(5, true, true, 'SOL', 'Synthetic Solana');

        createSynth(6, true, true, 'BNB', 'Synthetic Binance Coin');

        createSynth(7, true, true, 'ADA', 'Synthetic Cardano');

        vm.stopBroadcast();
    }
}
