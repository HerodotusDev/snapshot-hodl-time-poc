#[starknet::contract]
mod contract {
    use hdp_cairo::memorizer::header_memorizer::HeaderMemorizerTrait;
    use core::traits::TryInto;
    use hdp_cairo::{
        HDP, memorizer::header_memorizer::{HeaderKey, HeaderMemorizerImpl},
        memorizer::account_memorizer::{AccountKey, AccountMemorizerImpl},
        memorizer::storage_memorizer::{StorageKey, StorageMemorizerImpl},
        memorizer::block_tx_memorizer::{BlockTxKey, BlockTxMemorizerImpl}
    };
    use starknet::eth_signature::{verify_eth_signature};
    use starknet::{EthAddress, secp256_trait};

    #[storage]
    struct Storage {}

    const REQUIRED_MIN_HOLDING_PERIOD_IN_SECONDS: u256 = 604_800; // 1 week

    fn get_holding_period_in_seconds(
        hdp: @HDP,
        l1_chain_id: felt252,
        l1_start_block_number: felt252,
        l1_end_block_number: felt252
    ) -> u256 {
        let start_block_timestamp = hdp
            .header_memorizer
            .get_timestamp(
                HeaderKey { chain_id: l1_chain_id, block_number: l1_start_block_number }
            );

        let end_block_timestamp = hdp
            .header_memorizer
            .get_timestamp(HeaderKey { chain_id: l1_chain_id, block_number: l1_end_block_number });

        assert!(
            start_block_timestamp < end_block_timestamp, "End block must come after start block"
        );

        let holding_period_in_seconds = end_block_timestamp - start_block_timestamp;
        holding_period_in_seconds
    }

    fn get_token_balance(
        hdp: @HDP,
        l1_chain_id: felt252,
        l1_voter_address: felt252,
        l1_voting_token_address: felt252,
        voting_token_balance_slot: u256,
        block_number: felt252
    ) -> u256 {
        let token_balance = hdp
            .storage_memorizer
            .get_slot(
                StorageKey {
                    chain_id: l1_chain_id,
                    block_number: block_number,
                    address: l1_voting_token_address,
                    storage_slot: voting_token_balance_slot
                }
            );

        token_balance
    }

    fn get_missing_txns_count(
        hdp: @HDP,
        l1_chain_id: felt252,
        l1_voter_address: felt252,
        l1_start_block_number: felt252,
        l1_end_block_number: felt252
    ) -> (u256, u256) {
        let nonce_at_start_block: u256 = AccountMemorizerImpl::get_nonce(
            hdp.account_memorizer,
            AccountKey {
                chain_id: l1_chain_id,
                block_number: l1_start_block_number,
                address: l1_voter_address
            }
        );
        let nonce_at_end_block: u256 = AccountMemorizerImpl::get_nonce(
            hdp.account_memorizer,
            AccountKey {
                chain_id: l1_chain_id, block_number: l1_end_block_number, address: l1_voter_address
            }
        );
        let missing_txns_count = nonce_at_end_block - nonce_at_start_block - 1;
        (missing_txns_count, nonce_at_start_block)
    }


    fn normalize_v(v: u256, chain_id: felt252) -> u32 {
        if v == 0 {
            // Legacy transactions (v = 0x0)
            26
        } else if v == 1 {
            // Legacy transactions (v = 0x1)
            27
        } else if v > 35 {
            // EIP-155, EIP-2930, and EIP-4844 transactions
            let normalized_v = v + (chain_id.try_into().unwrap() * 2 + 35);
            normalized_v.try_into().unwrap()
        } else {
            panic!("Invalid v value for normalization")
        }
    }

    fn get_tx_nonce(
        hdp: @HDP,
        expected_sender: felt252,
        l1_chain_id: felt252,
        block_number: felt252,
        tx_index: felt252,
        tx_digest: u256
    ) -> u256 {
        let transaction_nonce = BlockTxMemorizerImpl::get_nonce(
            hdp.block_tx_memorizer,
            BlockTxKey { chain_id: l1_chain_id, block_number, index: tx_index }
        );

        let v = BlockTxMemorizerImpl::get_v(
            hdp.block_tx_memorizer,
            BlockTxKey { chain_id: l1_chain_id, block_number, index: tx_index }
        );
        let r = BlockTxMemorizerImpl::get_r(
            hdp.block_tx_memorizer,
            BlockTxKey { chain_id: l1_chain_id, block_number, index: tx_index }
        );
        let s = BlockTxMemorizerImpl::get_s(
            hdp.block_tx_memorizer,
            BlockTxKey { chain_id: l1_chain_id, block_number, index: tx_index }
        );

        let normalized_v = normalize_v(v, l1_chain_id);

        let expected_sender: EthAddress = expected_sender.try_into().unwrap();
        verify_eth_signature(
            tx_digest, secp256_trait::signature_from_vrs(normalized_v, r, s), expected_sender
        );

        transaction_nonce
    }

    #[external(v0)]
    pub fn main(
        ref self: ContractState,
        hdp: HDP,
        l1_chain_id: felt252,
        l1_voter_address: felt252,
        l1_voting_token_address: felt252,
        l1_voting_token_balance_slot: u256,
        l1_start_block_number: felt252,
        l1_end_block_number: felt252,
        txns_block_numbers: Array<felt252>,
        txns_indices: Array<felt252>,
        txns_digests: Array<u256>
    ) -> u256 {
        let holding_period_in_seconds = get_holding_period_in_seconds(
            @hdp, l1_chain_id.try_into().unwrap(), l1_start_block_number, l1_end_block_number
        );
        let token_balance_at_start = get_token_balance(
            @hdp,
            l1_chain_id.try_into().unwrap(),
            l1_voter_address,
            l1_voting_token_address,
            l1_voting_token_balance_slot,
            l1_end_block_number
        );
        let (missing_txns_count, nonce_at_start_block) = get_missing_txns_count(
            @hdp,
            l1_chain_id.try_into().unwrap(),
            l1_voter_address,
            l1_start_block_number,
            l1_end_block_number
        );

        if missing_txns_count > 0 {
            assert!(
                txns_block_numbers.len().into() == missing_txns_count,
                "Unexpected amount of transactions to check (block numbers)"
            );
            assert!(
                txns_indices.len().into() == missing_txns_count,
                "Unexpected amount of transactions to check (indices)"
            );
        }
        let mut checked_tx_idx = 0;
        loop {
            if checked_tx_idx == missing_txns_count {
                break 0;
            }
            let expected_tx_nonce = nonce_at_start_block + checked_tx_idx;

            let tx_block_number = *txns_block_numbers.at(checked_tx_idx.try_into().unwrap());
            let tx_nonce = get_tx_nonce(
                @hdp,
                l1_voter_address,
                l1_chain_id.try_into().unwrap(),
                tx_block_number,
                *txns_indices.at(checked_tx_idx.try_into().unwrap()),
                *txns_digests.at(checked_tx_idx.try_into().unwrap())
            );

            assert!(tx_nonce == expected_tx_nonce, "Unexpected transaction nonce");

            let token_balance_at_tx = get_token_balance(
                @hdp,
                l1_chain_id.try_into().unwrap(),
                l1_voter_address,
                l1_voting_token_address,
                l1_voting_token_balance_slot,
                tx_block_number
            );
            assert!(token_balance_at_tx >= token_balance_at_start);

            checked_tx_idx += 1;
        };

        if holding_period_in_seconds >= REQUIRED_MIN_HOLDING_PERIOD_IN_SECONDS {
            return 1;
        }
        return 0;
    }
}
