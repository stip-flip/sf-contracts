// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.6;

library Permit {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    function DOMAIN_TYPEHASH() internal pure returns (bytes32) {
        return
            keccak256(
                'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
            );
    }

    function PERMIT_TYPEHASH() internal pure returns (bytes32) {
        return
            keccak256(
                'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
            );
    }

    function DOMAIN_SEPARATOR(
        string memory name
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH(),
                    keccak256(bytes(name)),
                    keccak256(bytes('1')),
                    block.chainid,
                    address(this)
                )
            );
    }

    struct PermitParams {
        bytes32 domainSeparator;
        address owner;
        address spender;
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function permit(
        PermitParams memory p,
        mapping(address => uint) storage nonces,
        mapping(address => mapping(address => uint)) storage allowance
    ) public {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH(),
                p.owner,
                p.spender,
                p.value,
                nonces[p.owner],
                p.deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01', p.domainSeparator, structHash)
        );

        address recoveredAddress = ecrecover(digest, p.v, p.r, p.s);

        require(
            recoveredAddress != address(0) && recoveredAddress == p.owner,
            'INVALID_SIGNER'
        );

        require(block.timestamp <= p.deadline, 'EXPIRED');

        nonces[p.owner]++;

        allowance[p.owner][p.spender] = p.value;

        emit Approval(p.owner, p.spender, p.value);
    }
}
