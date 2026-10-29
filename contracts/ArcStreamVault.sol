// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Selector-only interface for Arc's native SLH-DSA-SHA2-128s (FIPS 205) verifier.
interface IArcPQ {
    function verifySlhDsaSha2128s(bytes calldata vk, bytes calldata message, bytes calldata sig)
        external
        view
        returns (bool);
}

/// @title ArcStreamVault
/// @notice Noncustodial milestone approval and payment accounting for ERC-20 USDC.
/// @dev The lifecycle is contractor submission, employer approval, then milestone release.
/// The employer controls approvals but cannot unilaterally refund submitted, unapproved work.
/// Employer refunds cover only unsubmitted, unapproved milestones; contractor termination
/// voluntarily waives unapproved work. Approved funds remain claimable after a refund.
/// Either party may propose a mutualCancel split of all remaining funds, including approved
/// obligations; only identical consent from the other current party executes the settlement.
/// Settlement records credits without transferring tokens; each party claims separately, so a
/// blocklisted recipient can only block its own claim. Contractor credit follows the current
/// contractor role and can be claimed after updateContractor; the employer has no rotation.
/// Unclaimed settlement credits remain included in the escrow's remaining balance.
/// Submission protects against unilateral employer refunds, not refusal to approve. Mutual
/// cancellation is the only dispute resolution when submitted work is not approved: no timeout,
/// arbiter, or unilateral payout exists. Cooperation is required to resolve such a dispute.
/// Only the current contractor can rotate its payout wallet; the employer cannot change it.
/// Rotation remains available after termination. USDC issuer restrictions still apply to
/// the new address and are not bypassed. A USDC-blocklisted contractor causes release to
/// revert, but does not affect refunds to an otherwise eligible employer.
/// Token-level restrictions on the vault or employer can
/// still prevent transfers. The constructor token must be trusted, standard, non-rebasing
/// USDC with six decimals; amounts are raw units (1 USDC = 1_000_000). No native gas-token
/// operations, administrator, recovery authority, or upgrade mechanism are provided.
/// At transaction boundaries, for standard USDC:
/// balanceOf(this) >= sum(totalDeposited - totalReleased - refundedAmounts) over all escrows.
/// Direct token donations are not assigned to an escrow and cannot be recovered.
/// Optional PQ 2FA uses SLH-DSA-SHA2-128s (FIPS 205), a hash-based post-quantum signature,
/// verified by Arc's native precompile on Arc Testnet (chain 5042002) and Arc mainnet.
/// The signed message is exactly the 32-byte pqSigningMessage digest, binding PQ_DOMAIN,
/// chainid, this vault, escrow id, and action (milestone index for release, milestoneCount
/// for refund). The employer selects an immutable 32-byte public key and is responsible
/// for custody of its secret key. SLH-DSA is stateless; one key may protect many escrows.
/// pqCommitment is keccak256(pqPublicKey), a UI/event fingerprint, not a separate secret.
/// Protection guards only employer-initiated release and refund. approveMilestone,
/// submitMilestoneWork, mutualCancel, claimSettlement, and updateContractor remain wallet-key
/// (ECDSA) only by design; adding PQ protection to them is an explicit non-goal. A stolen
/// wallet key can still approve milestones (enabling payment to the contractor), but cannot
/// initiate release or refund of a protected escrow without a valid PQ signature.
/// Losing the PQ secret key blocks employer release/refund; contractor claims remain
/// proof-free and mutualCancel remains the cooperative recovery path. If a hardfork ever
/// disables the precompile, protected employer actions fail; mutualCancel is the recovery path.
/// Signatures are not bound to transaction senders: a signature seen in the mempool can only
/// trigger the same single action, with release paying the current contractor and refund
/// paying the employer, never a caller-selected destination. Existing authorization still
/// applies. Protected release/refund costs roughly 380k gas including signature calldata.
contract ArcStreamVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Milestone {
        uint256 amount;
        string description;
        bool isApproved;
        bool isReleased;
        string workProofHash;
        bool isWorkSubmitted;
    }

    struct MutualCancelProposal {
        address proposer;
        uint256 contractorShare;
        uint256 employerShare;
    }

    struct EscrowAgreement {
        address employer;
        address contractor;
        uint256 totalDeposited;
        uint256 totalReleased;
        uint256 milestoneCount;
        bool isTerminated;
        bytes32 pqCommitment;
        bool isPQProtected;
        bytes pqPublicKey;
    }

    error Unauthorized();
    error InvalidToken();
    error InvalidContractor();
    error InvalidMilestoneCount();
    error ArrayLengthMismatch();
    error InvalidAmount();
    error EscrowNotFound();
    error MilestoneOutOfRange();
    error EscrowTerminated();
    error MilestoneAlreadyApproved();
    error MilestoneAlreadyReleased();
    error MilestoneNotApproved();
    error NothingToRefund();
    error UnexpectedTokenReceipt();
    error EmptyWorkProof();
    error WorkProofTooLong();
    error WorkNotSubmitted();
    error WorkAlreadySubmitted();
    error EscrowSettled();
    error NotSettled();
    error InvalidSplit();
    error InvalidQuantumProof();
    error InvalidPQPublicKey();
    error PQPrecompileUnavailable();

    /// @notice An SLH-DSA-SHA2-128s signature was verified; milestoneIndex is the action index.
    /// @dev Refund actions use milestoneCount; pqCommitment is the public key's keccak256 fingerprint.
    event QuantumProofVerified(uint256 indexed escrowId, uint256 milestoneIndex, bytes32 pqCommitment);

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed employer,
        address indexed contractor,
        uint256 total,
        uint256 milestoneCount
    );
    event MilestoneApproved(uint256 indexed escrowId, uint256 milestoneIndex, address indexed employer);
    event MilestoneReleased(
        uint256 indexed escrowId, uint256 milestoneIndex, address indexed contractor, uint256 amount
    );
    event EscrowRefunded(uint256 indexed escrowId, address indexed employer, uint256 amount);
    event ContractorUpdated(
        uint256 indexed escrowId, address indexed previousContractor, address indexed newContractor
    );

    event WorkSubmitted(uint256 indexed escrowId, uint256 milestoneIndex, string workProofHash);
    event MutualCancelProposed(
        uint256 indexed escrowId, address indexed proposer, uint256 contractorShare, uint256 employerShare
    );
    event EscrowMutuallyCancelled(uint256 indexed escrowId, uint256 contractorShare, uint256 employerShare);
    event SettlementClaimed(uint256 indexed escrowId, address indexed recipient, uint256 amount);
    event MutualCancelProposalCancelled(uint256 indexed escrowId, address indexed proposer);

    /// @notice Maximum proof length in bytes.
    uint256 public constant MAX_WORK_PROOF_LENGTH = 256;

    /// @notice Arc's native SLH-DSA-SHA2-128s (FIPS 205) signature verification precompile.
    address public constant ARC_PQ_PRECOMPILE = address(0x1800000000000000000000000000000000000004);

    /// @notice Required SLH-DSA-SHA2-128s public key length in bytes.
    uint256 public constant PQ_PUBLIC_KEY_LENGTH = 32;

    /// @notice Required SLH-DSA-SHA2-128s signature length in bytes.
    uint256 public constant PQ_SIGNATURE_LENGTH = 7856;

    /// @notice Domain separator included in every PQ signing digest.
    bytes32 public constant PQ_DOMAIN = keccak256("ArcStreamVault.PQ.v1");

    /// @notice Maximum number of milestones in a single escrow.
    uint256 public constant MAX_MILESTONES = 50;

    /// @notice Maximum historical index entries scanned per escrow page.
    uint256 public constant MAX_PAGE_SIZE = 100;

    /// @notice Constructor-supplied ERC-20 USDC token; never a hardcoded chain address.
    IERC20 public immutable usdc;

    /// @notice Number of created escrows; valid identifiers run from 1 through this value.
    uint256 public escrowCount;

    mapping(uint256 escrowId => EscrowAgreement) private escrows;
    mapping(uint256 escrowId => mapping(uint256 index => Milestone)) private milestones;

    mapping(address user => uint256[] escrowIds) private userEscrowIds;
    mapping(uint256 escrowId => mapping(address user => bool)) private isUserEscrowIndexed;

    /// @notice Number of submitted milestones awaiting approval per escrow.
    /// @dev Historical after termination or settlement; only active escrows use this refund guard.
    mapping(uint256 escrowId => uint256 count) public submittedUnapprovedCount;

    /// @notice Whether the escrow's remaining funds were settled by mutual cancellation.
    mapping(uint256 escrowId => bool settled) public isSettled;

    /// @notice Latest mutual cancellation proposal, replaced by any differing proposal.
    mapping(uint256 escrowId => MutualCancelProposal) public mutualCancelProposals;

    /// @notice Approved, unreleased obligations per escrow, including after refund termination.
    /// @dev Cleared on mutual settlement, which supersedes individual milestone obligations.
    mapping(uint256 escrowId => uint256 amount) public approvedPending;

    /// @notice Cumulative refunded principal per escrow, including claimed employer settlements.
    mapping(uint256 escrowId => uint256 amount) public refundedAmounts;

    /// @notice Unclaimed settlement credit belonging to the current contractor role.
    mapping(uint256 escrowId => uint256 amount) public contractorSettlementOwed;

    /// @notice Unclaimed settlement credit belonging to the employer, who cannot rotate.
    mapping(uint256 escrowId => uint256 amount) public employerSettlementOwed;

    /// @notice Select the ERC-20 USDC contract used by all escrows.
    /// @dev Deployment must select genuine six-decimal USDC; metadata is not consulted.
    /// @param usdcAddress Token contract address, not the native gas-token identifier.
    constructor(address usdcAddress) {
        if (usdcAddress == address(0) || usdcAddress.code.length == 0) revert InvalidToken();
        usdc = IERC20(usdcAddress);
    }

    /// @notice Fund a new escrow with the caller as employer.
    /// @dev Requires an existing allowance for the sum of amounts. Nonexact token receipts
    /// revert atomically. Solidity checked arithmetic rejects an overflowing total.
    /// A nonempty public key enables an SLH-DSA-SHA2-128s (FIPS 205) hash-based post-quantum
    /// signature second factor verified by Arc's native precompile. The employer is responsible
    /// for PQ secret key custody; the public key cannot be changed afterwards. The same key
    /// may protect many escrows, with chain, vault, escrow and action bound by pqSigningMessage.
    /// An empty-key availability probe rejects an absent precompile (success with no returndata);
    /// the live precompile reverts for that malformed key. No signature is needed at creation.
    /// Protection covers only employer release/refund, costing roughly 380k gas per protected
    /// action. Other lifecycle functions remain wallet-key (ECDSA) only by design. A stolen
    /// wallet key can approve milestones for contractor payment but cannot initiate protected
    /// release/refund without a PQ signature. Lost PQ keys or a hardfork disabling the precompile
    /// block employer release/refund, not contractor claims; mutualCancel is cooperative recovery.
    /// @param contractor Initial payout wallet; only the current contractor may rotate it.
    /// @param amounts Positive milestone amounts in six-decimal USDC base units.
    /// @param descriptions Descriptions corresponding to each milestone amount.
    /// @param pqPublicKey Immutable 32-byte SLH-DSA-SHA2-128s public key; empty disables protection.
    /// @return escrowId Newly created identifier, starting at 1.
    function createEscrow(
        address contractor,
        uint256[] calldata amounts,
        string[] calldata descriptions,
        bytes calldata pqPublicKey
    ) external nonReentrant returns (uint256 escrowId) {
        if (contractor == address(0) || contractor == msg.sender) revert InvalidContractor();
        uint256 count = amounts.length;
        if (count != descriptions.length) revert ArrayLengthMismatch();
        if (count == 0 || count > MAX_MILESTONES) revert InvalidMilestoneCount();
        if (pqPublicKey.length != 0) {
            if (pqPublicKey.length != PQ_PUBLIC_KEY_LENGTH) revert InvalidPQPublicKey();
            (bool ok, bytes memory ret) = ARC_PQ_PRECOMPILE.staticcall{gas: 100_000}(
                abi.encodeWithSelector(
                    IArcPQ.verifySlhDsaSha2128s.selector, bytes(""), bytes(""), bytes("")
                )
            );
            if (ok && ret.length == 0) revert PQPrecompileUnavailable();
        }

        escrowId = ++escrowCount;
        uint256 total;
        for (uint256 i; i < count;) {
            uint256 amount = amounts[i];
            if (amount == 0) revert InvalidAmount();
            total += amount;
            Milestone storage milestone = milestones[escrowId][i];
            milestone.amount = amount;
            milestone.description = descriptions[i];
            // i < count <= MAX_MILESTONES (50), so incrementing i cannot overflow.
            unchecked {
                ++i;
            }
        }

        EscrowAgreement storage agreement = escrows[escrowId];
        agreement.employer = msg.sender;
        agreement.contractor = contractor;
        agreement.totalDeposited = total;
        agreement.milestoneCount = count;
        if (pqPublicKey.length != 0) {
            agreement.pqPublicKey = pqPublicKey;
            agreement.pqCommitment = keccak256(pqPublicKey);
            agreement.isPQProtected = true;
        }
        _indexUserEscrow(escrowId, msg.sender);
        _indexUserEscrow(escrowId, contractor);

        emit EscrowCreated(escrowId, msg.sender, contractor, total, count);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), total);
        uint256 balanceAfter = usdc.balanceOf(address(this));
        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != total) {
            revert UnexpectedTokenReceipt();
        }
    }

    /// @notice Rotate the contractor's payout wallet for an existing escrow.
    /// @dev Only the current contractor may call, including after termination; the employer
    /// cannot change the contractor. USDC issuer restrictions still apply to the new wallet
    /// and are not bypassed. No token transfer occurs.
    /// @param escrowId Existing escrow identifier.
    /// @param newContractor New wallet, distinct from zero, the employer, and the current contractor.
    function updateContractor(uint256 escrowId, address newContractor) external {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        address previousContractor = agreement.contractor;
        if (msg.sender != previousContractor) revert Unauthorized();
        if (
            newContractor == address(0) || newContractor == agreement.employer
                || newContractor == previousContractor
        ) revert InvalidContractor();

        agreement.contractor = newContractor;
        _indexUserEscrow(escrowId, newContractor);
        if (mutualCancelProposals[escrowId].proposer == previousContractor) {
            delete mutualCancelProposals[escrowId];
            emit MutualCancelProposalCancelled(escrowId, previousContractor);
        }
        emit ContractorUpdated(escrowId, previousContractor, newContractor);
    }

    /// @notice Submit or replace work proof for an unapproved milestone.
    /// @dev Only the current contractor may submit. Approval freezes the proof, and
    /// termination permanently disables submission. First submission blocks employer refunds.
    /// @param escrowId Existing escrow identifier.
    /// @param milestoneIndex Zero-based milestone index.
    /// @param workProofHash Nonempty proof reference, at most MAX_WORK_PROOF_LENGTH bytes.
    function submitMilestoneWork(uint256 escrowId, uint256 milestoneIndex, string calldata workProofHash)
        external
        nonReentrant
    {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        if (msg.sender != agreement.contractor) revert Unauthorized();
        if (agreement.isTerminated) revert EscrowTerminated();
        if (milestoneIndex >= agreement.milestoneCount) revert MilestoneOutOfRange();
        Milestone storage milestone = milestones[escrowId][milestoneIndex];
        if (milestone.isReleased) revert MilestoneAlreadyReleased();
        if (milestone.isApproved) revert MilestoneAlreadyApproved();
        uint256 proofLength = bytes(workProofHash).length;
        if (proofLength == 0) revert EmptyWorkProof();
        if (proofLength > MAX_WORK_PROOF_LENGTH) revert WorkProofTooLong();

        if (!milestone.isWorkSubmitted) {
            milestone.isWorkSubmitted = true;
            submittedUnapprovedCount[escrowId] += 1;
        }
        milestone.workProofHash = workProofHash;

        emit WorkSubmitted(escrowId, milestoneIndex, workProofHash);
    }

    /// @notice Irrevocably approve a submitted milestone for payment to the contractor.
    /// @dev Only the employer may approve; termination permanently disables approvals.
    /// @param escrowId Existing escrow identifier.
    /// @param milestoneIndex Zero-based milestone index.
    function approveMilestone(uint256 escrowId, uint256 milestoneIndex) external nonReentrant {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        if (msg.sender != agreement.employer) revert Unauthorized();
        if (agreement.isTerminated) revert EscrowTerminated();
        if (milestoneIndex >= agreement.milestoneCount) revert MilestoneOutOfRange();
        Milestone storage milestone = milestones[escrowId][milestoneIndex];
        if (milestone.isReleased) revert MilestoneAlreadyReleased();
        if (milestone.isApproved) revert MilestoneAlreadyApproved();

        if (!milestone.isWorkSubmitted) revert WorkNotSubmitted();

        milestone.isApproved = true;
        submittedUnapprovedCount[escrowId] -= 1;
        approvedPending[escrowId] += milestone.amount;

        emit MilestoneApproved(escrowId, milestoneIndex, msg.sender);
    }

    /// @notice Pay an approved milestone directly to its designated contractor.
    /// @dev Either party may call, including after refund termination, but never after mutual
    /// settlement. All accounting is updated before transfer and rolled back if USDC rejects it.
    /// Only a protected escrow's employer supplies an SLH-DSA-SHA2-128s (FIPS 205) signature
    /// over the exact 32-byte pqSigningMessage(escrowId, milestoneIndex) digest, verified by
    /// Arc's native precompile before effects. Contractor claims never require a proof.
    /// Signatures are not bound to transaction senders; a mempool copy can only trigger this
    /// same single action, paying the current contractor, never a caller-selected destination.
    /// Lost PQ keys or a disabled precompile block employer release/refund, not contractor
    /// claims; mutualCancel remains cooperative recovery. Other lifecycle functions remain
    /// wallet-key (ECDSA) only by design. Protected release costs roughly 380k gas.
    /// @param escrowId Existing escrow identifier.
    /// @param milestoneIndex Zero-based milestone index and PQ signing action.
    /// @param pqProof Raw 7856-byte signature; ignored for contractors and unprotected escrows.
    function releaseMilestone(uint256 escrowId, uint256 milestoneIndex, bytes calldata pqProof)
        external
        nonReentrant
    {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        address contractor = agreement.contractor;
        if (msg.sender != agreement.employer && msg.sender != contractor) revert Unauthorized();
        if (isSettled[escrowId]) revert EscrowSettled();
        if (milestoneIndex >= agreement.milestoneCount) revert MilestoneOutOfRange();
        Milestone storage milestone = milestones[escrowId][milestoneIndex];
        if (milestone.isReleased) revert MilestoneAlreadyReleased();
        if (!milestone.isApproved) revert MilestoneNotApproved();

        uint256 amount = milestone.amount;
        uint256 remaining = agreement.totalDeposited - agreement.totalReleased - refundedAmounts[escrowId];
        if (amount > remaining) revert InvalidAmount();
        if (agreement.isPQProtected && msg.sender == agreement.employer) {
            _verifyQuantumProof(escrowId, agreement, milestoneIndex, pqProof);
        }
        milestone.isReleased = true;
        agreement.totalReleased += amount;
        approvedPending[escrowId] -= amount;

        emit MilestoneReleased(escrowId, milestoneIndex, contractor, amount);
        usdc.safeTransfer(contractor, amount);
    }

    /// @notice Terminate and refund all unapproved milestone principal to the employer.
    /// @dev Either party may call without the other's signature. Employer refunds cover only
    /// unsubmitted, unapproved milestones: the employer must approve submitted work or reach
    /// a mutualCancel agreement. Contractor invocation voluntarily waives all unapproved work,
    /// including submitted work, and is not blocked by submission. Approved funds remain claimable.
    /// Runs in constant time; reverts without termination if nothing is refundable. Successful
    /// termination prevents all further submissions.
    /// Only a protected escrow's employer supplies an SLH-DSA-SHA2-128s (FIPS 205) signature
    /// over the exact 32-byte pqSigningMessage(escrowId, agreement.milestoneCount) digest,
    /// verified by Arc's native precompile before effects; contractor voluntary waivers do not.
    /// Signatures are not bound to transaction senders; a mempool copy can only trigger this
    /// same single action, paying the employer, never a caller-selected destination. Lost PQ
    /// keys or a disabled precompile block employer release/refund, not contractor claims;
    /// mutualCancel remains cooperative recovery. Other lifecycle functions remain wallet-key
    /// (ECDSA) only by design. Protected refund costs roughly 380k gas.
    /// @param escrowId Existing escrow identifier.
    /// @param pqProof Raw 7856-byte signature; ignored for contractors and unprotected escrows.
    function refundRemaining(uint256 escrowId, bytes calldata pqProof) external nonReentrant {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        address employer = agreement.employer;
        if (msg.sender != employer && msg.sender != agreement.contractor) revert Unauthorized();
        if (agreement.isTerminated) revert EscrowTerminated();

        if (msg.sender == employer && submittedUnapprovedCount[escrowId] != 0) revert WorkAlreadySubmitted();

        uint256 amount = agreement.totalDeposited - agreement.totalReleased - approvedPending[escrowId];
        if (amount == 0) revert NothingToRefund();
        if (agreement.isPQProtected && msg.sender == employer) {
            _verifyQuantumProof(escrowId, agreement, agreement.milestoneCount, pqProof);
        }
        agreement.isTerminated = true;
        refundedAmounts[escrowId] = amount;

        emit EscrowRefunded(escrowId, employer, amount);
        usdc.safeTransfer(employer, amount);
    }

    /// @notice Propose or accept a two-party split of all remaining escrow funds.
    /// @dev Either the employer or current contractor may propose; the other accepts by calling
    /// with identical shares. Repeating one's own proposal or supplying different shares replaces
    /// the proposal without transfers. Shares must sum to the current unreleased, unrefunded
    /// balance, including approved and submitted work; intervening payments require a fresh split.
    /// Available even after refund termination while funds remain. Execution supersedes milestone
    /// obligations and permanently prevents further releases. Execution only records credits;
    /// each party claims separately via claimSettlement, so a blocklisted party can only block
    /// its own claim. Contractor credit follows the current contractor role, which can rotate
    /// via updateContractor before claiming; the employer has no rotation. Unclaimed credits
    /// remain in the unreleased, unrefunded balance until claimed.
    /// This is the only dispute resolution when work is submitted but the employer refuses approval:
    /// no timeout or arbiter exists, and neither party can force acceptance of a proposed split.
    /// @param escrowId Existing escrow identifier.
    /// @param contractorShare Amount to pay the current contractor, in raw USDC units.
    /// @param employerShare Amount to refund to the employer, in raw USDC units.
    function mutualCancel(uint256 escrowId, uint256 contractorShare, uint256 employerShare)
        external
        nonReentrant
    {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        address employer = agreement.employer;
        address contractor = agreement.contractor;
        if (msg.sender != employer && msg.sender != contractor) revert Unauthorized();
        if (isSettled[escrowId]) revert EscrowSettled();

        uint256 remaining = agreement.totalDeposited - agreement.totalReleased - refundedAmounts[escrowId];
        if (remaining == 0) revert NothingToRefund();
        if (contractorShare > remaining || employerShare != remaining - contractorShare) revert InvalidSplit();

        MutualCancelProposal storage proposal = mutualCancelProposals[escrowId];
        if (
            proposal.proposer == address(0) || proposal.proposer == msg.sender
                || proposal.contractorShare != contractorShare || proposal.employerShare != employerShare
        ) {
            proposal.proposer = msg.sender;
            proposal.contractorShare = contractorShare;
            proposal.employerShare = employerShare;

            emit MutualCancelProposed(escrowId, msg.sender, contractorShare, employerShare);
            return;
        }

        delete mutualCancelProposals[escrowId];
        isSettled[escrowId] = true;
        agreement.isTerminated = true;
        approvedPending[escrowId] = 0;
        contractorSettlementOwed[escrowId] = contractorShare;
        employerSettlementOwed[escrowId] = employerShare;

        emit EscrowMutuallyCancelled(escrowId, contractorShare, employerShare);
    }

    /// @notice Claim only the caller's own mutual cancellation settlement credit.
    /// @dev Each party claims separately; a blocklisted party can only block its own claim.
    /// Contractor credit follows the current contractor role, which may rotate via
    /// updateContractor before claiming. The employer has no rotation. Accounting changes
    /// only on claim, before the event and transfer; a rejected transfer rolls them back.
    /// @param escrowId Existing, mutually settled escrow identifier.
    function claimSettlement(uint256 escrowId) external nonReentrant {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        address employer = agreement.employer;
        address contractor = agreement.contractor;
        if (msg.sender != employer && msg.sender != contractor) revert Unauthorized();
        if (!isSettled[escrowId]) revert NotSettled();

        uint256 amount;
        if (msg.sender == employer) {
            amount = employerSettlementOwed[escrowId];
            if (amount == 0) revert NothingToRefund();
            refundedAmounts[escrowId] += amount;
            employerSettlementOwed[escrowId] = 0;
        } else {
            amount = contractorSettlementOwed[escrowId];
            if (amount == 0) revert NothingToRefund();
            agreement.totalReleased += amount;
            contractorSettlementOwed[escrowId] = 0;
        }

        emit SettlementClaimed(escrowId, msg.sender, amount);
        usdc.safeTransfer(msg.sender, amount);
    }

    /// @notice Withdraw the caller's pending mutual cancellation proposal without moving funds.
    /// @dev Only the stored proposer may cancel; missing proposals revert Unauthorized.
    /// @param escrowId Escrow identifier with a pending proposal.
    function cancelMutualCancelProposal(uint256 escrowId) external {
        if (mutualCancelProposals[escrowId].proposer != msg.sender) revert Unauthorized();

        delete mutualCancelProposals[escrowId];

        emit MutualCancelProposalCancelled(escrowId, msg.sender);
    }

    /// @notice Read an existing escrow's agreement, including its termination status.
    /// @param escrowId Existing escrow identifier; unknown identifiers revert.
    /// @return agreement Stored agreement fields in their declared order.
    function getEscrow(uint256 escrowId) external view returns (EscrowAgreement memory agreement) {
        return _getEscrow(escrowId);
    }

    /// @notice Read an existing milestone's amount, description, work proof, and payment status.
    /// @dev Unapproved milestones after refund termination are refunded, not released. Mutual
    /// settlement supersedes all remaining milestones without changing their individual flags;
    /// consult isSettled and the escrow's termination status alongside these historical fields.
    /// @param escrowId Existing escrow identifier; unknown identifiers revert.
    /// @param index Zero-based index; out-of-range indices revert.
    /// @return milestone Stored milestone fields in their declared order.
    function getMilestone(uint256 escrowId, uint256 index) external view returns (Milestone memory milestone) {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        if (index >= agreement.milestoneCount) revert MilestoneOutOfRange();
        return milestones[escrowId][index];
    }

    /// @notice Read all milestones of an existing escrow in milestone order.
    /// @param escrowId Existing escrow identifier; unknown identifiers revert.
    /// @return result All milestone fields, including submitted proof and payment status.
    function getMilestones(uint256 escrowId) external view returns (Milestone[] memory result) {
        EscrowAgreement storage agreement = _getEscrow(escrowId);
        uint256 count = agreement.milestoneCount;
        result = new Milestone[](count);
        for (uint256 i; i < count; ++i) {
            result[i] = milestones[escrowId][i];
        }
    }

    /// @notice Read escrows where the user is currently employer or contractor, in index order.
    /// @dev For small histories only; results and historical index size are unbounded.
    /// Spam-prone users should use getUserEscrowsPage. Scans storage once and copies matches
    /// from a memory buffer without sorting. Rotation can place older ids after newer ones;
    /// the frontend may sort if creation order is needed. Filters rotated-out contractors.
    /// @param user Employer or current contractor wallet to query.
    /// @return result Matching escrow ids, with no duplicates.
    function getUserEscrows(address user) external view returns (uint256[] memory result) {
        uint256[] storage indexedIds = userEscrowIds[user];
        uint256 length = indexedIds.length;
        uint256[] memory matches = new uint256[](length);
        uint256 count;
        for (uint256 i; i < length; ++i) {
            uint256 escrowId = indexedIds[i];
            EscrowAgreement storage agreement = escrows[escrowId];
            if (agreement.employer == user || agreement.contractor == user) {
                matches[count] = escrowId;
                ++count;
            }
        }

        result = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            result[i] = matches[i];
        }
    }

    /// @notice Read the historical index length, including rotated-out contractor entries.
    /// @param user Wallet whose historical index is queried.
    /// @return Number of entries in the historical index, not the current-role match count.
    function getUserEscrowCount(address user) external view returns (uint256) {
        return userEscrowIds[user].length;
    }

    /// @notice Read current-role escrow matches from a bounded slice of the historical index.
    /// @dev Scans at most limit entries, clamped to MAX_PAGE_SIZE and the remaining length.
    /// Filters rotated-out contractors, so a page can be empty before the index ends.
    /// Results use index order; rotation can place older ids after newer ones, and the frontend
    /// may sort. A start beyond the end is clamped to the length; zero limit scans nothing.
    /// @param user Employer or current contractor wallet to query.
    /// @param start Historical index offset, not an offset into filtered matches.
    /// @param limit Maximum index entries to scan, clamped without reverting.
    /// @return ids Matching escrow ids in the scanned slice, with no duplicates.
    /// @return nextStart Clamped start plus scanned entries; index length when finished.
    function getUserEscrowsPage(address user, uint256 start, uint256 limit)
        external
        view
        returns (uint256[] memory ids, uint256 nextStart)
    {
        uint256[] storage indexedIds = userEscrowIds[user];
        uint256 length = indexedIds.length;
        if (start > length) start = length;
        if (limit > MAX_PAGE_SIZE) limit = MAX_PAGE_SIZE;
        uint256 remaining = length - start;
        if (limit > remaining) limit = remaining;
        nextStart = start + limit;

        uint256[] memory matches = new uint256[](limit);
        uint256 count;
        for (uint256 i = start; i < nextStart; ++i) {
            uint256 escrowId = indexedIds[i];
            EscrowAgreement storage agreement = escrows[escrowId];
            if (agreement.employer == user || agreement.contractor == user) {
                matches[count] = escrowId;
                ++count;
            }
        }

        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = matches[i];
        }
    }

    /// @notice Return the exact 32-byte message digest signed for a protected employer action.
    /// @dev Sign these digest bytes directly as the SLH-DSA-SHA2-128s message, without an
    /// Ethereum signed-message prefix or further hashing. Verification passes abi.encodePacked
    /// of this digest to Arc's native precompile. This helper does not validate escrow existence
    /// or action range and does not bind a transaction sender.
    /// @param escrowId Escrow identifier included in the signing domain.
    /// @param action Milestone index for release, or the escrow's milestoneCount for refund.
    /// @return Domain-bound keccak256 digest of PQ_DOMAIN, chainid, vault, escrow and action.
    function pqSigningMessage(uint256 escrowId, uint256 action) public view returns (bytes32) {
        return keccak256(abi.encode(PQ_DOMAIN, block.chainid, address(this), escrowId, action));
    }

    /// @dev Verify a raw SLH-DSA-SHA2-128s (FIPS 205) signature using the immutable public key
    /// and exact 32-byte domain-bound digest via Arc's normal ABI selector call (vk, message, sig).
    /// Wrong lengths, failed calls, malformed return data and any result other than word 1
    /// revert InvalidQuantumProof. Existing release/termination state makes each action one-time;
    /// the stateless public key is reusable across escrows. No PQ secret is stored or revealed.
    /// Emits before effects and token transfers; transaction failure rolls back the event.
    function _verifyQuantumProof(
        uint256 escrowId,
        EscrowAgreement storage agreement,
        uint256 action,
        bytes calldata pqProof
    ) private {
        if (pqProof.length != PQ_SIGNATURE_LENGTH) revert InvalidQuantumProof();
        (bool ok, bytes memory ret) = ARC_PQ_PRECOMPILE.staticcall(
            abi.encodeWithSelector(
                IArcPQ.verifySlhDsaSha2128s.selector,
                agreement.pqPublicKey,
                abi.encodePacked(pqSigningMessage(escrowId, action)),
                pqProof
            )
        );
        if (!ok || ret.length != 32) revert InvalidQuantumProof();
        if (abi.decode(ret, (uint256)) != 1) revert InvalidQuantumProof();

        emit QuantumProofVerified(escrowId, action, agreement.pqCommitment);
    }

    function _indexUserEscrow(uint256 escrowId, address user) private {
        if (!isUserEscrowIndexed[escrowId][user]) {
            isUserEscrowIndexed[escrowId][user] = true;
            userEscrowIds[user].push(escrowId);
        }
    }

    function _getEscrow(uint256 escrowId) private view returns (EscrowAgreement storage agreement) {
        agreement = escrows[escrowId];
        if (agreement.employer == address(0)) revert EscrowNotFound();
    }
}
