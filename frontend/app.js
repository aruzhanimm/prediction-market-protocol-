let provider;
let signer;
let userAddress;

const CONFIG = window.APP_CONFIG;

const stateNames = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
];

const erc20VotesAbi = [
  "function balanceOf(address account) view returns (uint256)",
  "function getVotes(address account) view returns (uint256)",
  "function delegates(address account) view returns (address)",
  "function delegate(address delegatee)",
];

const erc1155Abi = [
  "function isApprovedForAll(address account, address operator) view returns (bool)",
  "function setApprovalForAll(address operator, bool approved)",
  "function balanceOf(address account, uint256 id) view returns (uint256)",
];

const marketAmmAbi = [
  "function getReserves() view returns (uint256 reserveYes, uint256 reserveNo, uint256 k)",
  "function addLiquidity(uint256 yesAmount, uint256 noAmount, uint256 minLPOut) returns (uint256 lpMinted)",
  "function swap(bool buyYes, uint256 amountIn, uint256 minAmountOut) returns (uint256 amountOut)",
  "function balanceOf(address account) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
];

const governorAbi = [
  "function state(uint256 proposalId) view returns (uint8)",
  "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
];

const vaultAbi = [
  "function balanceOf(address account) view returns (uint256)",
  "function totalAssets() view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256 shares)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)",
];

function $(id) {
  return document.getElementById(id);
}

function setStatus(message) {
  $("statusMessage").textContent = message;
}

function showError(error) {
  const message = humanizeError(error);
  $("errorMessage").textContent = message;
  $("errorMessage").classList.remove("hidden");
}

function clearError() {
  $("errorMessage").textContent = "";
  $("errorMessage").classList.add("hidden");
}

function humanizeError(error) {
  const text = String(error?.shortMessage || error?.reason || error?.message || error);

  if (text.includes("user rejected") || text.includes("User denied")) {
    return "Transaction was rejected in the wallet.";
  }

  if (text.includes("insufficient funds") || text.includes("Insufficient")) {
    return "Insufficient balance for this transaction.";
  }

  if (text.includes("wrong network") || text.includes("unsupported chain")) {
    return "Wrong network. Please switch to Arbitrum Sepolia.";
  }

  if (text.includes("execution reverted")) {
    return "Transaction reverted. Check token balances, approvals, proposal state, or input values.";
  }

  if (text.includes("max fee per gas less than block base fee")) {
    return "Gas fee is too low for the current block. Please retry the transaction or increase Max Fee in MetaMask.";
  }
  return "Operation failed. Please check wallet, network, balances, approvals, and input values.";
}

async function connectWallet() {
  clearError();

  if (!window.ethereum) {
    showError("MetaMask is not installed.");
    return;
  }

  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  userAddress = await signer.getAddress();

  $("walletAddress").textContent = userAddress;
  setStatus("Wallet connected.");

  await checkNetwork();
  await refreshReads();
}

async function checkNetwork() {
  const network = await provider.getNetwork();
  const currentChainId = Number(network.chainId);

  if (currentChainId !== CONFIG.chain.chainIdDecimal) {
    $("networkStatus").textContent = `Wrong network (${currentChainId}). Expected Arbitrum Sepolia.`;
    return false;
  }

  $("networkStatus").textContent = "Arbitrum Sepolia";
  return true;
}

async function switchNetwork() {
  clearError();

  if (!window.ethereum) {
    showError("MetaMask is not installed.");
    return;
  }

  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CONFIG.chain.chainIdHex }],
    });
  } catch (error) {
    if (error.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [CONFIG.chain],
      });
    } else {
      showError(error);
      return;
    }
  }

  provider = new ethers.BrowserProvider(window.ethereum);
  signer = await provider.getSigner();
  await checkNetwork();
}

function requireWallet() {
  if (!provider || !signer || !userAddress) {
    throw new Error("Connect MetaMask first.");
  }
}

function getContracts() {
  const govToken = new ethers.Contract(CONFIG.addresses.governanceToken, erc20VotesAbi, signer);
  const outcomeToken = new ethers.Contract(CONFIG.addresses.outcomeShareToken, erc1155Abi, signer);
  const amm = new ethers.Contract(CONFIG.addresses.marketAMM, marketAmmAbi, signer);
  const governor = new ethers.Contract(CONFIG.addresses.myGovernor, governorAbi, signer);
  const vault = new ethers.Contract(CONFIG.addresses.feeVault, vaultAbi, signer);

  return { govToken, outcomeToken, amm, governor, vault };
}

async function refreshReads() {
  clearError();

  try {
    requireWallet();

    const correctNetwork = await checkNetwork();
    if (!correctNetwork) {
      showError("Wrong network. Please switch to Arbitrum Sepolia.");
      return;
    }

    const { govToken, amm, vault } = getContracts();

    const [balance, votes, delegateAddress, reserves, vaultShares, vaultAssets] = await Promise.all([
      govToken.balanceOf(userAddress),
      govToken.getVotes(userAddress),
      govToken.delegates(userAddress),
      amm.getReserves(),
      vault.balanceOf(userAddress),
      vault.totalAssets(),
    ]);

    $("predBalance").textContent = `${ethers.formatEther(balance)} PRED`;
    $("votingPower").textContent = `${ethers.formatEther(votes)} votes`;
    $("delegateAddress").textContent = delegateAddress;
    $("reserveYes").textContent = ethers.formatEther(reserves[0]);
    $("reserveNo").textContent = ethers.formatEther(reserves[1]);
    $("reserveK").textContent = reserves[2].toString();
    $("vaultShares").textContent = ethers.formatEther(vaultShares);
    $("vaultTotalAssets").textContent = ethers.formatEther(vaultAssets);

    setStatus("Reads refreshed.");
  } catch (error) {
    showError(error);
  }
}

async function delegateVotes() {
  clearError();

  try {
    requireWallet();

    const { govToken } = getContracts();
    const input = $("delegateToInput").value.trim();
    const delegatee = input || userAddress;

    const tx = await govToken.delegate(delegatee, await getGasOverrides());
    setStatus(`Delegate transaction sent: ${tx.hash}`);

    await tx.wait();
    setStatus("Delegation confirmed.");
    await refreshReads();
  } catch (error) {
    showError(error);
  }
}

async function approveAmm() {
  clearError();

  try {
    requireWallet();

    const { outcomeToken } = getContracts();
    const tx = await outcomeToken.setApprovalForAll(
        CONFIG.addresses.marketAMM,
        true,
        await getGasOverrides()
    );

    setStatus(`Approval transaction sent: ${tx.hash}`);
    await tx.wait();

    setStatus("AMM approved for ERC-1155 outcome tokens.");
  } catch (error) {
    showError(error);
  }
}

async function addLiquidity() {
  clearError();

  try {
    requireWallet();

    const yesInput = $("yesAmountInput").value.trim();
    const noInput = $("noAmountInput").value.trim();

    if (!yesInput || !noInput) {
      throw new Error("Enter YES and NO amounts.");
    }

    const yesAmount = ethers.parseEther(yesInput);
    const noAmount = ethers.parseEther(noInput);

    const { amm } = getContracts();
    const tx = await amm.addLiquidity(yesAmount, noAmount, 0, await getGasOverrides());

    setStatus(`Add liquidity transaction sent: ${tx.hash}`);
    await tx.wait();

    setStatus("Liquidity added.");
    await refreshReads();
  } catch (error) {
    showError(error);
  }
}

async function swap() {
  clearError();

  try {
    requireWallet();

    const buyYes = $("swapDirectionInput").value === "true";
    const amountInput = $("swapAmountInput").value.trim();

    if (!amountInput) {
      throw new Error("Enter swap amount.");
    }

    const amountIn = ethers.parseEther(amountInput);

    const { amm } = getContracts();
    const tx = await amm.swap(buyYes, amountIn, 0, await getGasOverrides());

    setStatus(`Swap transaction sent: ${tx.hash}`);
    await tx.wait();

    setStatus("Swap confirmed.");
    await refreshReads();
  } catch (error) {
    showError(error);
  }
}

async function getProposalState() {
  clearError();

  try {
    requireWallet();

    const proposalId = $("proposalIdInput").value.trim();

    if (!proposalId) {
      throw new Error("Enter proposalId.");
    }

    const { governor } = getContracts();
    const state = await governor.state(proposalId);

    $("proposalState").textContent = stateNames[Number(state)] || `Unknown (${state})`;
    setStatus("Proposal state loaded.");
  } catch (error) {
    showError(error);
  }
}

async function vote(support) {
  clearError();

  try {
    requireWallet();

    const proposalId = $("proposalIdInput").value.trim();

    if (!proposalId) {
      throw new Error("Enter proposalId.");
    }

    const { governor } = getContracts();
    const tx = await governor.castVote(proposalId, support, await getGasOverrides());

    setStatus(`Vote transaction sent: ${tx.hash}`);
    await tx.wait();

    setStatus("Vote confirmed.");
    await getProposalState();
  } catch (error) {
    showError(error);
  }
}

async function loadSubgraphData() {
  clearError();

  try {
    const query = `
      {
        markets(first: 5, orderBy: createdAt, orderDirection: desc) {
          id
          marketId
          question
          status
          outcome
          totalShares
          createdAt
        }
        trades(first: 5, orderBy: timestamp, orderDirection: desc) {
          id
          market
          trader
          buyYes
          amountIn
          amountOut
          timestamp
        }
        governanceProposals(first: 5, orderBy: createdAt, orderDirection: desc) {
          id
          proposalId
          proposer
          description
          state
          forVotes
          againstVotes
          abstainVotes
          startBlock
          endBlock
        }
      }
    `;

    const response = await fetch(CONFIG.subgraphUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query }),
    });

    const json = await response.json();

    if (json.errors) {
      throw new Error(json.errors.map((e) => e.message).join("\n"));
    }

    renderSubgraphData(json.data);
    $("subgraphOutput").textContent = JSON.stringify(json.data, null, 2);
    setStatus("Subgraph data loaded.");
  } catch (error) {
    showError(error);
  }
}
function renderSubgraphData(data) {
  renderMarkets(data.markets || []);
  renderTrades(data.trades || []);
  renderProposals(data.governanceProposals || []);
}

function renderMarkets(markets) {
  const container = $("marketsList");

  if (markets.length === 0) {
    container.innerHTML = `<p class="empty-state">No markets indexed yet.</p>`;
    return;
  }

  container.innerHTML = markets
    .map((market) => {
      const outcomeText =
        market.outcome === null || market.outcome === undefined
          ? "Not resolved"
          : market.outcome
            ? "YES"
            : "NO";

      return `
        <div class="list-item">
          <p><strong>Market #${market.marketId}</strong></p>
          <p>${escapeHtml(market.question)}</p>
          <p>Status: <span class="pill">${market.status}</span></p>
          <p>Outcome: ${outcomeText}</p>
          <p>Total shares: ${market.totalShares}</p>
        </div>
      `;
    })
    .join("");
}

function renderTrades(trades) {
  const container = $("tradesList");

  if (trades.length === 0) {
    container.innerHTML = `<p class="empty-state">No trades indexed yet.</p>`;
    return;
  }

  container.innerHTML = trades
    .map((trade) => {
      return `
        <div class="list-item">
          <p><strong>Trade</strong> ${trade.buyYes ? "Buy YES" : "Buy NO"}</p>
          <p>Trader: ${shortAddress(trade.trader)}</p>
          <p>Amount in: ${trade.amountIn}</p>
          <p>Amount out: ${trade.amountOut}</p>
          <p>Market: ${trade.market}</p>
        </div>
      `;
    })
    .join("");
}

function renderProposals(proposals) {
  const container = $("proposalsList");

  if (proposals.length === 0) {
    container.innerHTML = `
      <p class="empty-state">
        No governance proposals indexed yet. Create a proposal first or paste proposalId manually.
      </p>
    `;
    return;
  }

  container.innerHTML = proposals
    .map((proposal) => {
      return `
        <div class="list-item">
          <p><strong>Proposal ID:</strong> ${proposal.proposalId}</p>
          <p>${escapeHtml(proposal.description || "No description")}</p>
          <p>State: <span class="pill">${proposal.state}</span></p>
          <p>For: ${proposal.forVotes}</p>
          <p>Against: ${proposal.againstVotes}</p>
          <p>Abstain: ${proposal.abstainVotes}</p>
          <button class="useProposalBtn" data-proposal-id="${proposal.proposalId}">
            Use Proposal
          </button>
        </div>
      `;
    })
    .join("");

  document.querySelectorAll(".useProposalBtn").forEach((button) => {
    button.addEventListener("click", () => {
      $("proposalIdInput").value = button.dataset.proposalId;
      setStatus("Proposal ID copied into vote form.");
    });
  });
}

function shortAddress(address) {
  if (!address || address.length < 10) {
    return address || "-";
  }

  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function getGasOverrides() {
  const feeData = await provider.getFeeData();

  if (feeData.maxFeePerGas && feeData.maxPriorityFeePerGas) {
    return {
      maxFeePerGas: (feeData.maxFeePerGas * 130n) / 100n,
      maxPriorityFeePerGas: (feeData.maxPriorityFeePerGas * 130n) / 100n,
    };
  }

  if (feeData.gasPrice) {
    return {
      gasPrice: (feeData.gasPrice * 130n) / 100n,
    };
  }

  return {};
}

function setupListeners() {
  $("connectWalletBtn").addEventListener("click", connectWallet);
  $("switchNetworkBtn").addEventListener("click", switchNetwork);
  $("refreshReadsBtn").addEventListener("click", refreshReads);
  $("delegateBtn").addEventListener("click", delegateVotes);
  $("approveAmmBtn").addEventListener("click", approveAmm);
  $("addLiquidityBtn").addEventListener("click", addLiquidity);
  $("swapBtn").addEventListener("click", swap);
  $("proposalStateBtn").addEventListener("click", getProposalState);
  $("loadSubgraphBtn").addEventListener("click", loadSubgraphData);

  document.querySelectorAll(".voteBtn").forEach((button) => {
    button.addEventListener("click", () => {
      vote(Number(button.dataset.support));
    });
  });

  if (window.ethereum) {
    window.ethereum.on("accountsChanged", () => window.location.reload());
    window.ethereum.on("chainChanged", () => window.location.reload());
  }
}

setupListeners();