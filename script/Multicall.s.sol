import 'forge-std/Script.sol';
import './lib/Strings.sol';
import './lib/Multicall.sol';

function addressToString(address a) pure returns (string memory) {
    return Strings.toHexString(uint(uint160(a)), 20);
}

contract MulticallScript is Script {
    function run() public {
        string memory path = string(
            abi.encodePacked(
                './addresses/',
                Strings.toString(block.chainid),
                '/multicall'
            )
        );

        vm.startBroadcast();

        MultiCallUtils multicall = new MultiCallUtils();

        vm.writeLine(path, 'MULTICALL: ');
        vm.writeLine(path, addressToString(address(multicall)));

        vm.stopBroadcast();
    }
}
