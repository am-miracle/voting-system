/// Module: voting_system

module voting_system::voting_system {
    use std::string::{Self, String};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;

    // Error codes
    const E_VOTING_ENDED: u64 = 1;
    const E_VOTING_NOT_ENDED: u64 = 2;
    const E_ALREADY_VOTED: u64 = 3;
    const E_INVALID_OPTION: u64 = 4;
    // const E_NOT_AUTHORIZED: u64 = 5;

    // Structs
    public struct VotingSystem has key {
        id: UID,
        title: String,
        description: String,
        options: vector<String>,
        votes: Table<u8, u64>, // option_index -> vote_count
        voters: Table<address, bool>, // track who has voted
        creator: address,
        start_time: u64,
        end_time: u64,
        total_votes: u64,
    }

    public struct VotingCap has key, store {
        id: UID,
        voting_id: address,
    }

    // Events
    public struct VotingCreated has copy, drop {
        voting_id: address,
        title: String,
        creator: address,
        end_time: u64,
    }

    public struct VoteCast has copy, drop {
        voting_id: address,
        voter: address,
        option_index: u8,
        option_name: String,
    }

    public struct VotingEnded has copy, drop {
        voting_id: address,
        total_votes: u64,
        winning_option: String,
        winning_votes: u64,
    }

    // Create a new voting system
    #[allow(lint(self_transfer))]
    public fun create_voting(
        title: vector<u8>,
        description: vector<u8>,
        options: vector<vector<u8>>,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        let end_time = current_time + duration_ms;

        // Convert byte vectors to strings
        let title_str = string::utf8(title);
        let description_str = string::utf8(description);
        let mut options_str = vector::empty<String>();
        let mut i = 0;
        while (i < vector::length(&options)) {
            let option = vector::borrow(&options, i);
            vector::push_back(&mut options_str, string::utf8(*option));
            i = i + 1;
        };

        let voting_id = object::new(ctx);
        let voting_address = object::uid_to_address(&voting_id);

        // Initialize vote counts for each option
        let mut votes = table::new<u8, u64>(ctx);
        let mut j = 0;
        while (j < vector::length(&options_str)) {
            table::add(&mut votes, (j as u8), 0);
            j = j + 1;
        };

        let voting_system = VotingSystem {
            id: voting_id,
            title: title_str,
            description: description_str,
            options: options_str,
            votes,
            voters: table::new<address, bool>(ctx),
            creator: tx_context::sender(ctx),
            start_time: current_time,
            end_time,
            total_votes: 0,
        };

        // Create capability for the creator
        let cap = VotingCap {
            id: object::new(ctx),
            voting_id: voting_address,
        };

        // Emit event
        event::emit(VotingCreated {
            voting_id: voting_address,
            title: title_str,
            creator: tx_context::sender(ctx),
            end_time,
        });

        transfer::share_object(voting_system);
        transfer::transfer(cap, tx_context::sender(ctx));
    }

    // Cast a vote
    public fun cast_vote(
        voting: &mut VotingSystem,
        option_index: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        let voter = tx_context::sender(ctx);

        // Check if voting is still active
        assert!(current_time < voting.end_time, E_VOTING_ENDED);

        // Check if voter hasn't already voted
        assert!(!table::contains(&voting.voters, voter), E_ALREADY_VOTED);

        // Check if option is valid
        assert!((option_index as u64) < vector::length(&voting.options), E_INVALID_OPTION);

        // Record the vote
        table::add(&mut voting.voters, voter, true);

        let current_votes = table::borrow_mut(&mut voting.votes, option_index);
        *current_votes = *current_votes + 1;

        voting.total_votes = voting.total_votes + 1;

        // Emit event
        let option_name = *vector::borrow(&voting.options, (option_index as u64));
        event::emit(VoteCast {
            voting_id: object::uid_to_address(&voting.id),
            voter,
            option_index,
            option_name,
        });
    }

    // End voting and get results (only creator can call this)
    public fun end_voting(
        voting: &mut VotingSystem,
        _cap: &VotingCap,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);

        // Check if voting period has ended
        assert!(current_time >= voting.end_time, E_VOTING_NOT_ENDED);
        // assert!(tx_context::sender(ctx) == voting.creator, E_NOT_AUTHORIZED);

        // Find winning option
        let mut winning_option_index = 0u8;
        let mut max_votes = 0u64;
        let mut i = 0u8;

        while ((i as u64) < vector::length(&voting.options)) {
            let vote_count = *table::borrow(&voting.votes, i);
            if (vote_count > max_votes) {
                max_votes = vote_count;
                winning_option_index = i;
            };
            i = i + 1;
        };

        let winning_option = *vector::borrow(&voting.options, (winning_option_index as u64));

        // Emit event
        event::emit(VotingEnded {
            voting_id: object::uid_to_address(&voting.id),
            total_votes: voting.total_votes,
            winning_option,
            winning_votes: max_votes,
        });
    }

    // View functions
    public fun get_voting_info(voting: &VotingSystem): (String, String, u64, u64, u64) {
        (voting.title, voting.description, voting.start_time, voting.end_time, voting.total_votes)
    }

    public fun get_options(voting: &VotingSystem): vector<String> {
        voting.options
    }

    public fun get_vote_count(voting: &VotingSystem, option_index: u8): u64 {
        if (table::contains(&voting.votes, option_index)) {
            *table::borrow(&voting.votes, option_index)
        } else {
            0
        }
    }

    public fun has_voted(voting: &VotingSystem, voter: address): bool {
        table::contains(&voting.voters, voter)
    }

    public fun is_voting_active(voting: &VotingSystem, clock: &Clock): bool {
        let current_time = clock::timestamp_ms(clock);
        current_time >= voting.start_time && current_time < voting.end_time
    }

    // Get results (can be called by anyone after voting ends)
    public fun get_results(voting: &VotingSystem): (vector<String>, vector<u64>) {
        let mut vote_counts = vector::empty<u64>();
        let mut i = 0u8;

        while ((i as u64) < vector::length(&voting.options)) {
            let count = *table::borrow(&voting.votes, i);
            vector::push_back(&mut vote_counts, count);
            i = i + 1;
        };

        (voting.options, vote_counts)
    }
}

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions


