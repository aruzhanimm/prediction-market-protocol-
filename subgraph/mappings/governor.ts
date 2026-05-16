import { BigInt } from "@graphprotocol/graph-ts";
import {
  ProposalCreated,
  VoteCast,
  ProposalQueued,
  ProposalExecuted,
} from "../generated/MyGovernor/MyGovernor";
import { GovernanceProposal } from "../generated/schema";

export function handleProposalCreated(event: ProposalCreated): void {
  let id = event.params.proposalId.toString();
  let proposal = new GovernanceProposal(id);

  proposal.proposalId = event.params.proposalId;
  proposal.proposer = event.params.proposer;
  proposal.description = event.params.description;
  proposal.state = "Pending";
  proposal.forVotes = BigInt.fromI32(0);
  proposal.againstVotes = BigInt.fromI32(0);
  proposal.abstainVotes = BigInt.fromI32(0);
  proposal.eta = null;
  proposal.startBlock = event.params.voteStart;
  proposal.endBlock = event.params.voteEnd;
  proposal.createdAt = event.block.timestamp;
  proposal.txHash = event.transaction.hash;

  proposal.save();
}

export function handleVoteCast(event: VoteCast): void {
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());

  if (proposal == null) {
    return;
  }

  // support: 0 = Against, 1 = For, 2 = Abstain
  if (event.params.support == 1) {
    proposal.forVotes = proposal.forVotes.plus(event.params.weight);
    proposal.state = "Active";
  } else if (event.params.support == 0) {
    proposal.againstVotes = proposal.againstVotes.plus(event.params.weight);
    proposal.state = "Active";
  } else if (event.params.support == 2) {
    proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight);
    proposal.state = "Active";
  }

  proposal.save();
}

export function handleProposalQueued(event: ProposalQueued): void {
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());

  if (proposal == null) {
    return;
  }

  proposal.state = "Queued";
  proposal.eta = event.params.etaSeconds;

  proposal.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());

  if (proposal == null) {
    return;
  }

  proposal.state = "Executed";

  proposal.save();
}