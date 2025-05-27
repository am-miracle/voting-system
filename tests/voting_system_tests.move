#[test_only]
module voting_system::voting_system_tests {
    use voting_system::voting_system::{Self, VotingSystem, VotingCap, E_VOTING_ENDED, E_VOTING_NOT_ENDED, E_ALREADY_VOTED, E_INVALID_OPTION};
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use std::string;

    // Test constants
    const CREATOR: address = @0xA;
    const VOTER1: address = @0xB;
    const VOTER2: address = @0xC;
    const VOTER3: address = @0xD;


    const DAY_MS: u64 = 86400000; // 24 hours in milliseconds

    // Helper function to create a basic voting scenario
    fun create_test_voting(scenario: &mut Scenario, clock: &Clock) {
        test_scenario::next_tx(scenario, CREATOR);
        {
            let ctx = test_scenario::ctx(scenario);
            voting_system::create_voting(
                b"Should we upgrade the protocol?",
                b"Vote on whether to implement the new protocol upgrade",
                vector[b"Yes", b"No", b"Abstain"],
                DAY_MS, // 24 hour voting period
                clock,
                ctx
            );
        };
    }

    #[test]
    fun test_create_voting() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // Check that VotingSystem was created and shared
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            assert!(test_scenario::has_most_recent_shared<VotingSystem>(), 0);
            let voting = test_scenario::take_shared<VotingSystem>(&scenario);

            // Verify voting info
            let (title, description, start_time, end_time, total_votes) = 
                voting_system::get_voting_info(&voting);

            assert!(title == string::utf8(b"Should we upgrade the protocol?"), 1);
            assert!(description == string::utf8(b"Vote on whether to implement the new protocol upgrade"), 2);
            assert!(total_votes == 0, 3);
            assert!(end_time - start_time == DAY_MS, 4);

            // Verify options
            let options = voting_system::get_options(&voting);
            assert!(vector::length(&options) == 3, 5);
            assert!(*vector::borrow(&options, 0) == string::utf8(b"Yes"), 6);
            assert!(*vector::borrow(&options, 1) == string::utf8(b"No"), 7);
            assert!(*vector::borrow(&options, 2) == string::utf8(b"Abstain"), 8);

            // Check initial vote counts
            assert!(voting_system::get_vote_count(&voting, 0) == 0, 9);
            assert!(voting_system::get_vote_count(&voting, 1) == 0, 10);
            assert!(voting_system::get_vote_count(&voting, 2) == 0, 11);

            test_scenario::return_shared(voting);
        };

        // Check that VotingCap was transferred to creator
        {
            assert!(test_scenario::has_most_recent_for_sender<VotingCap>(&scenario), 12);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_cast_vote() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // VOTER1 casts a vote for option 0 (Yes)
        test_scenario::next_tx(&mut scenario, VOTER1);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            assert!(voting_system::is_voting_active(&voting, &clock), 13);
            assert!(!voting_system::has_voted(&voting, VOTER1), 14);

            voting_system::cast_vote(&mut voting, 0, &clock, ctx);

            // Verify vote was recorded
            assert!(voting_system::get_vote_count(&voting, 0) == 1, 15);
            assert!(voting_system::has_voted(&voting, VOTER1), 16);

            let (_, _, _, _, total_votes) = voting_system::get_voting_info(&voting);
            assert!(total_votes == 1, 17);

            test_scenario::return_shared(voting);
        };

        // VOTER2 casts a vote for option 1 (No)
        test_scenario::next_tx(&mut scenario, VOTER2);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            voting_system::cast_vote(&mut voting, 1, &clock, ctx);

            assert!(voting_system::get_vote_count(&voting, 1) == 1, 18);
            assert!(voting_system::has_voted(&voting, VOTER2), 19);

            test_scenario::return_shared(voting);
        };

        // VOTER3 casts a vote for option 0 (Yes)
        test_scenario::next_tx(&mut scenario, VOTER3);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            voting_system::cast_vote(&mut voting, 0, &clock, ctx);

            assert!(voting_system::get_vote_count(&voting, 0) == 2, 20);
            assert!(voting_system::get_vote_count(&voting, 1) == 1, 21);
            assert!(voting_system::get_vote_count(&voting, 2) == 0, 22);

            let (_, _, _, _, total_votes) = voting_system::get_voting_info(&voting);
            assert!(total_votes == 3, 23);

            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = E_ALREADY_VOTED)]
    fun test_double_vote_fails() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // VOTER1 casts first vote
        test_scenario::next_tx(&mut scenario, VOTER1);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            voting_system::cast_vote(&mut voting, 0, &clock, ctx);
            test_scenario::return_shared(voting);
        };

        // VOTER1 tries to vote again - should fail
        test_scenario::next_tx(&mut scenario, VOTER1);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            voting_system::cast_vote(&mut voting, 1, &clock, ctx); // This should abort
            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = E_INVALID_OPTION)]
    fun test_invalid_option_fails() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, VOTER1);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            // Try to vote for option 3 (doesn't exist, only 0, 1, 2 are valid)
            voting_system::cast_vote(&mut voting, 3, &clock, ctx); // This should abort
            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = E_VOTING_ENDED)]
    fun test_vote_after_end_fails() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // Fast forward time past voting end
        clock::increment_for_testing(&mut clock, DAY_MS + 1000);

        test_scenario::next_tx(&mut scenario, VOTER1);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            assert!(!voting_system::is_voting_active(&voting, &clock), 24);

            // Try to vote after voting has ended - should fail
            voting_system::cast_vote(&mut voting, 0, &clock, ctx); // This should abort
            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_end_voting() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // Cast some votes first
        test_scenario::next_tx(&mut scenario, VOTER1);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            voting_system::cast_vote(&mut voting, 0, &clock, ctx); // Yes
            test_scenario::return_shared(voting);
        };

        test_scenario::next_tx(&mut scenario, VOTER2);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            voting_system::cast_vote(&mut voting, 0, &clock, ctx); // Yes
            test_scenario::return_shared(voting);
        };

        test_scenario::next_tx(&mut scenario, VOTER3);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            voting_system::cast_vote(&mut voting, 1, &clock, ctx); // No
            test_scenario::return_shared(voting);
        };

        // Fast forward past voting end time
        clock::increment_for_testing(&mut clock, DAY_MS + 1000);

        // Creator ends the voting
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let cap = test_scenario::take_from_sender<VotingCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            voting_system::end_voting(&mut voting, &cap, &clock, ctx);

            // Verify results can be retrieved
            let (options, vote_counts) = voting_system::get_results(&voting);
            assert!(vector::length(&options) == 3, 25);
            assert!(vector::length(&vote_counts) == 3, 26);
            assert!(*vector::borrow(&vote_counts, 0) == 2, 27); // Yes: 2 votes
            assert!(*vector::borrow(&vote_counts, 1) == 1, 28); // No: 1 vote
            assert!(*vector::borrow(&vote_counts, 2) == 0, 29); // Abstain: 0 votes

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = E_VOTING_NOT_ENDED)]
    fun test_end_voting_early_fails() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // Try to end voting before time is up
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let cap = test_scenario::take_from_sender<VotingCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            // This should fail because voting period hasn't ended
            voting_system::end_voting(&mut voting, &cap, &clock, ctx);

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // #[test, expected_failure(abort_code = E_NOT_AUTHORIZED)]
    // fun test_non_creator_end_voting_fails() {
    //     let mut scenario = test_scenario::begin(CREATOR);
    //     let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    //     create_test_voting(&mut scenario, &clock);

    //     // Fast forward past voting end time
    //     clock::increment_for_testing(&mut clock, DAY_MS + 1000);

    //     // Non-creator tries to end voting
    //     test_scenario::next_tx(&mut scenario, VOTER1);
    //     {
    //         let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
    //         let ctx = test_scenario::ctx(&mut scenario);

    //         // Create a fake cap (this wouldn't work in practice, but for test)
    //         let fake_cap = test_scenario::take_from_address<VotingCap>(&scenario, CREATOR);

    //         // This should fail because VOTER1 is not the creator
    //         voting_system::end_voting(&mut voting, &fake_cap, &clock, ctx);

    //         test_scenario::return_to_address(CREATOR, fake_cap);
    //         test_scenario::return_shared(voting);
    //     };

    //     clock::destroy_for_testing(clock);
    //     test_scenario::end(scenario);
    // }

    #[test]
    fun test_get_results() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        create_test_voting(&mut scenario, &clock);

        // Cast votes to create interesting results
        let voters = vector[VOTER1, VOTER2, VOTER3];
        let votes = vector[0u8, 0u8, 1u8]; // Two "Yes", one "No"

        let mut i = 0;
        while (i < vector::length(&voters)) {
            let voter = *vector::borrow(&voters, i);
            let vote_option = *vector::borrow(&votes, i);

            test_scenario::next_tx(&mut scenario, voter);
            {
                let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
                let ctx = test_scenario::ctx(&mut scenario);
                voting_system::cast_vote(&mut voting, vote_option, &clock, ctx);
                test_scenario::return_shared(voting);
            };

            i = i + 1;
        };

        // Check results
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let voting = test_scenario::take_shared<VotingSystem>(&scenario);

            let (options, vote_counts) = voting_system::get_results(&voting);

            // Verify options are correct
            assert!(*vector::borrow(&options, 0) == string::utf8(b"Yes"), 30);
            assert!(*vector::borrow(&options, 1) == string::utf8(b"No"), 31);
            assert!(*vector::borrow(&options, 2) == string::utf8(b"Abstain"), 32);

            // Verify vote counts
            assert!(*vector::borrow(&vote_counts, 0) == 2, 33); // Yes: 2 votes
            assert!(*vector::borrow(&vote_counts, 1) == 1, 34); // No: 1 vote  
            assert!(*vector::borrow(&vote_counts, 2) == 0, 35); // Abstain: 0 votes

            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_voting_lifecycle() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        // 1. Create voting
        create_test_voting(&mut scenario, &clock);

        // 2. Multiple users vote - using separate vectors for voters and choices
        let voters = vector[VOTER1, VOTER2, VOTER3, @0xE];
        let choices = vector[0u8, 1u8, 0u8, 2u8]; // Yes, No, Yes, Abstain

        let mut i = 0;
        while (i < vector::length(&voters)) {
            let voter = *vector::borrow(&voters, i);
            let choice = *vector::borrow(&choices, i);

            test_scenario::next_tx(&mut scenario, voter);
            {
                let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
                let ctx = test_scenario::ctx(&mut scenario);

                assert!(voting_system::is_voting_active(&voting, &clock), 36);
                voting_system::cast_vote(&mut voting, choice, &clock, ctx);

                test_scenario::return_shared(voting);
            };

            i = i + 1;
        };

        // 3. Verify intermediate state
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let voting = test_scenario::take_shared<VotingSystem>(&scenario);

            let (_, _, _, _, total_votes) = voting_system::get_voting_info(&voting);
            assert!(total_votes == 4, 37);

            assert!(voting_system::get_vote_count(&voting, 0) == 2, 38); // Yes
            assert!(voting_system::get_vote_count(&voting, 1) == 1, 39); // No
            assert!(voting_system::get_vote_count(&voting, 2) == 1, 40); // Abstain

            test_scenario::return_shared(voting);
        };

        // 4. Fast forward and end voting
        clock::increment_for_testing(&mut clock, DAY_MS + 1000);

        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let mut voting = test_scenario::take_shared<VotingSystem>(&scenario);
            let cap = test_scenario::take_from_sender<VotingCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            assert!(!voting_system::is_voting_active(&voting, &clock), 41);
            voting_system::end_voting(&mut voting, &cap, &clock, ctx);

            // 5. Verify final results
            let (_options, vote_counts) = voting_system::get_results(&voting);
            assert!(*vector::borrow(&vote_counts, 0) == 2, 42); // Yes wins with 2 votes
            assert!(*vector::borrow(&vote_counts, 1) == 1, 43); // No: 1 vote
            assert!(*vector::borrow(&vote_counts, 2) == 1, 44); // Abstain: 1 vote

            test_scenario::return_to_sender(&scenario, cap);
            test_scenario::return_shared(voting);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}