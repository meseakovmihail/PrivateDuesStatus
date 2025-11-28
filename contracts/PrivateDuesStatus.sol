// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Private Membership Dues — Status Only (Zama FHEVM)
 *
 * What is stored:
 *  - For each member: encrypted paidThrough (epoch seconds, euint32).
 *  - Public grace period in days (uint16) — not sensitive.
 *
 * What is revealed:
 *  - Only the boolean status "IN_GOOD_STANDING / OVERDUE", as encrypted ebool.
 *  - Optionally that ebool can be marked publicly decryptable.
 *
 * No sums/amounts on-chain; updates to paidThrough are submitted as encrypted values
 * by owner/treasurer after off-chain settlement.
 */

import {
    FHE,
    ebool,
    euint32,
    externalEuint32
} from "@fhevm/solidity/lib/FHE.sol";

import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract PrivateDuesStatus is ZamaEthereumConfig {
    /* ───────── Meta / Ownership ───────── */

    function version() external pure returns (string memory) {
        return "PrivateDuesStatus/1.0.0";
    }

    address public owner;
    address public treasurer;

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    modifier onlyAdmin() { require(msg.sender == owner || msg.sender == treasurer, "Not admin"); _; }

    constructor() {
        owner = msg.sender;
        treasurer = msg.sender;
        graceDays = 7; // default 7 days
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    function setTreasurer(address newTreasurer) external onlyOwner {
        require(newTreasurer != address(0), "Zero treasurer");
        treasurer = newTreasurer;
    }

    /* ───────── Config ───────── */

    /// @notice grace period in whole days (public, not sensitive)
    uint16 public graceDays;

    event GraceUpdated(uint16 daysOld, uint16 daysNew);

    function setGraceDays(uint16 days_) external onlyOwner {
        emit GraceUpdated(graceDays, days_);
        graceDays = days_;
    }

    /* ───────── Storage ───────── */

    /// @dev Encrypted "paid through" timestamp per member (epoch seconds)
    mapping(address => euint32) private _paidThrough;

    event MemberRegistered(address indexed member, bytes32 paidThroughHandle);
    event MemberUpdated(address indexed member, bytes32 paidThroughHandle);
    event StatusCheckedPrivate(address indexed caller, address indexed member, bytes32 statusHandle);
    event StatusCheckedPublic(address indexed caller, address indexed member, bytes32 statusHandle);

    /* ───────── Admin: register / update (encrypted) ───────── */

    /**
     * @notice Create or update member's encrypted paidThrough (epoch seconds).
     * @dev Inputs must share the same proof only if you batch; here it's a single value.
     *      The new value is set to max(current, provided) to be monotonic non-decreasing.
     */
    function setPaidThroughEncrypted(
        address member,
        externalEuint32 paidThroughExt,
        bytes calldata proof
    ) external onlyAdmin {
        require(member != address(0), "Zero member");

        // Deserialize input with attestation
        euint32 incoming = FHE.fromExternal(paidThroughExt, proof);
        FHE.allowThis(incoming);

        euint32 current = _paidThrough[member];
        if (!_exists(member)) {
            // First-time registration
            _paidThrough[member] = incoming;
            FHE.allowThis(_paidThrough[member]);
            emit MemberRegistered(member, FHE.toBytes32(_paidThrough[member]));
            return;
        }

        // Monotonic update: max(current, incoming)
        ebool ge = FHE.ge(incoming, current);
        euint32 updated = FHE.select(ge, incoming, current);

        _paidThrough[member] = updated;
        FHE.allowThis(_paidThrough[member]);

        emit MemberUpdated(member, FHE.toBytes32(_paidThrough[member]));
    }

    /// @dev helper: whether mapping cell was ever initialized (paidThrough > 0)
    function _exists(address member) internal view returns (bool) {
        // We can't decrypt in view; rely on zero-bytes32 sentinel check instead.
        // If not set, FHE.toBytes32(euint32) returns 0x0 for the default value.
        return FHE.toBytes32(_paidThrough[member]) != bytes32(0);
    }

    /* ───────── Status checks ───────── */

    /**
     * @notice Compute encrypted status for a member and grant decryption to msg.sender.
     *         IN_GOOD_STANDING = (paidThrough + grace) >= now.
     * @return statusCt ebool ciphertext (1 = in good standing, 0 = overdue)
     */
    function checkStatusPrivate(address member) external returns (ebool statusCt) {
        require(_exists(member), "Member not registered");

        // now and grace in seconds
        uint32 nowSec = uint32(block.timestamp);
        uint32 graceSec = uint32(graceDays) * 1 days;

        euint32 nowCt    = FHE.asEuint32(nowSec);
        euint32 graceCt  = FHE.asEuint32(graceSec);

        // paidThrough + grace >= now ?
        euint32 paidPlus = FHE.add(_paidThrough[member], graceCt);
        ebool ok         = FHE.ge(paidPlus, nowCt);

        // ACL: allow caller private decryption; and reuse within contract
        FHE.allow(ok, msg.sender);
        FHE.allowThis(ok);

        emit StatusCheckedPrivate(msg.sender, member, FHE.toBytes32(ok));
        return ok;
    }

    /**
     * @notice Compute encrypted status and mark it as publicly decryptable.
     *         Anyone can read the result via Relayer SDK publicDecrypt.
     */
    function checkStatusPublic(address member) external returns (ebool statusCt) {
        require(_exists(member), "Member not registered");

        uint32 nowSec = uint32(block.timestamp);
        uint32 graceSec = uint32(graceDays) * 1 days;

        euint32 nowCt    = FHE.asEuint32(nowSec);
        euint32 graceCt  = FHE.asEuint32(graceSec);

        euint32 paidPlus = FHE.add(_paidThrough[member], graceCt);
        ebool ok         = FHE.ge(paidPlus, nowCt);

        // Make publicly decryptable (global readability)
        FHE.makePubliclyDecryptable(ok);
        FHE.allowThis(ok);

        emit StatusCheckedPublic(msg.sender, member, FHE.toBytes32(ok));
        return ok;
    }

    /* ───────── Debug / Ops helpers (optional) ───────── */

    /// @notice Return handle of member's encrypted paidThrough (for audits). Decryption depends on ACL/public flags.
    function getPaidThroughHandle(address member) external view returns (bytes32) {
        return FHE.toBytes32(_paidThrough[member]);
    }

    /// @notice Owner can force-reset a member (sets to zero-epoch).
    function resetMember(address member) external onlyOwner {
        require(member != address(0), "Zero member");
        _paidThrough[member] = FHE.asEuint32(0);
        FHE.allowThis(_paidThrough[member]);
    }
}
