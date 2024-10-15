// This is example contract of using HDP with account memorizer 
// Sum of balances of accounts in block number list and returns that value.
// Full HDP supports header, account and storage. 

#[starknet::contract]
mod contract {
    use hdp_cairo::{HDP, memorizer::account_memorizer::{AccountKey, AccountMemorizerImpl}};

    #[storage]
    struct Storage {}

    #[external(v0)]
    pub fn main(
        ref self: ContractState, hdp: HDP, mut block_number_list: Array<u32>, address: felt252
    ) -> u256 {
        let mut sum: u256 = 0;
        loop {
            match block_number_list.pop_front() {
                Option::Some(block_number) => {
                    sum += hdp
                        .account_memorizer
                        .get_balance(
                            AccountKey {
                                chain_id: 11155111,
                                block_number: block_number.into(),
                                address: address
                            }
                        )
                },
                Option::None => { break; },
            }
        };
        sum
    }
}