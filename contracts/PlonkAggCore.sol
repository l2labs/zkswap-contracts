pragma solidity >=0.5.0 <0.7.0;
pragma experimental ABIEncoderV2;

import "./PlonkCoreLib.sol";

contract Plonk4AggVerifierWithAccessToDNext {
    using PairingsBn254 for PairingsBn254.G1Point;
    using PairingsBn254 for PairingsBn254.G2Point;
    using PairingsBn254 for PairingsBn254.Fr;

    using TranscriptLibrary for TranscriptLibrary.Transcript;


    uint256 constant ZERO = 0;
    uint256 constant ONE = 1;
    uint256 constant TWO = 2;
    uint256 constant THREE = 3;
    uint256 constant FOUR = 4;

    uint256 constant STATE_WIDTH = 4;
    uint256 constant NUM_DIFFERENT_GATES = 2;
    uint256 constant NUM_SETUP_POLYS_FOR_MAIN_GATE = 7;
    uint256 constant NUM_SETUP_POLYS_RANGE_CHECK_GATE = 0;
    uint256 constant ACCESSIBLE_STATE_POLYS_ON_NEXT_STEP = 1;
    uint256 constant NUM_GATE_SELECTORS_OPENED_EXPLICITLY = 1;

    uint256 constant RECURSIVE_CIRCUIT_INPUT_COMMITMENT_MASK = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant LIMB_WIDTH = 68;

    struct VerificationKey {
        uint256 domain_size;
        uint256 num_inputs;
        PairingsBn254.Fr omega;
        PairingsBn254.G1Point[NUM_SETUP_POLYS_FOR_MAIN_GATE + NUM_SETUP_POLYS_RANGE_CHECK_GATE] gate_setup_commitments;
        PairingsBn254.G1Point[NUM_DIFFERENT_GATES] gate_selector_commitments;
        PairingsBn254.G1Point[STATE_WIDTH] copy_permutation_commitments;
        PairingsBn254.Fr[STATE_WIDTH-1] copy_permutation_non_residues;
        PairingsBn254.G2Point g2_x;
    }

    struct Proof {
        uint256[] input_values;
        PairingsBn254.G1Point[STATE_WIDTH] wire_commitments;
        PairingsBn254.G1Point copy_permutation_grand_product_commitment;
        PairingsBn254.G1Point[STATE_WIDTH] quotient_poly_commitments;
        PairingsBn254.Fr[STATE_WIDTH] wire_values_at_z;
        PairingsBn254.Fr[ACCESSIBLE_STATE_POLYS_ON_NEXT_STEP] wire_values_at_z_omega;
        PairingsBn254.Fr[NUM_GATE_SELECTORS_OPENED_EXPLICITLY] gate_selector_values_at_z;
        PairingsBn254.Fr copy_grand_product_at_z_omega;
        PairingsBn254.Fr quotient_polynomial_at_z;
        PairingsBn254.Fr linearization_polynomial_at_z;
        PairingsBn254.Fr[STATE_WIDTH-1] permutation_polynomials_at_z;

        PairingsBn254.G1Point opening_at_z_proof;
        PairingsBn254.G1Point opening_at_z_omega_proof;
    }

    struct PartialVerifierState {
        PairingsBn254.Fr alpha;
        PairingsBn254.Fr beta;
        PairingsBn254.Fr gamma;
        PairingsBn254.Fr v;
        PairingsBn254.Fr u;
        PairingsBn254.Fr z;
        PairingsBn254.Fr[] cached_lagrange_evals;
    }

    function evaluate_lagrange_poly_out_of_domain(
        uint256 poly_num,
        uint256 domain_size,
        PairingsBn254.Fr memory omega,
        PairingsBn254.Fr memory at
    ) internal view returns (PairingsBn254.Fr memory res) {
        require(poly_num < domain_size);
        PairingsBn254.Fr memory one = PairingsBn254.new_fr(1);
        PairingsBn254.Fr memory omega_power = omega.pow(poly_num);
        res = at.pow(domain_size);
        res.sub_assign(one);
        require(res.value != 0); // Vanishing polynomial can not be zero at point `at`
        res.mul_assign(omega_power);

        PairingsBn254.Fr memory den = PairingsBn254.copy(at);
        den.sub_assign(omega_power);
        den.mul_assign(PairingsBn254.new_fr(domain_size));

        den = den.inverse();

        res.mul_assign(den);
    }

    function batch_evaluate_lagrange_poly_out_of_domain(
        uint256[] memory poly_nums,
        uint256 domain_size,
        PairingsBn254.Fr memory omega,
        PairingsBn254.Fr memory at
    ) internal view returns (PairingsBn254.Fr[] memory res) {
        PairingsBn254.Fr memory one = PairingsBn254.new_fr(1);
        PairingsBn254.Fr memory tmp_1 = PairingsBn254.new_fr(0);
        PairingsBn254.Fr memory tmp_2 = PairingsBn254.new_fr(domain_size);
        PairingsBn254.Fr memory vanishing_at_z = at.pow(domain_size);
        vanishing_at_z.sub_assign(one);
        // we can not have random point z be in domain
        require(vanishing_at_z.value != 0);
        PairingsBn254.Fr[] memory nums = new PairingsBn254.Fr[](poly_nums.length);
        PairingsBn254.Fr[] memory dens = new PairingsBn254.Fr[](poly_nums.length);
        // numerators in a form omega^i * (z^n - 1)
        // denoms in a form (z - omega^i) * N
        for (uint i = 0; i < poly_nums.length; i++) {
            tmp_1 = omega.pow(poly_nums[i]); // power of omega
            nums[i].assign(vanishing_at_z);
            nums[i].mul_assign(tmp_1);

            dens[i].assign(at); // (X - omega^i) * N
            dens[i].sub_assign(tmp_1);
            dens[i].mul_assign(tmp_2); // mul by domain size
        }

        PairingsBn254.Fr[] memory partial_products = new PairingsBn254.Fr[](poly_nums.length);
        partial_products[0].assign(PairingsBn254.new_fr(1));
        for (uint i = 1; i < dens.length - 1; i++) {
            partial_products[i].assign(dens[i-1]);
            partial_products[i].mul_assign(dens[i]);
        }

        tmp_2.assign(partial_products[partial_products.length - 1]);
        tmp_2.mul_assign(dens[dens.length - 1]);
        tmp_2 = tmp_2.inverse(); // tmp_2 contains a^-1 * b^-1 (with! the last one)

        for (uint i = dens.length - 1; i < dens.length; i--) {
            dens[i].assign(tmp_2); // all inversed
            dens[i].mul_assign(partial_products[i]); // clear lowest terms
            tmp_2.mul_assign(dens[i]);
        }

        for (uint i = 0; i < nums.length; i++) {
            nums[i].mul_assign(dens[i]);
        }

        return nums;
    }

    function evaluate_vanishing(
        uint256 domain_size,
        PairingsBn254.Fr memory at
    ) internal view returns (PairingsBn254.Fr memory res) {
        res = at.pow(domain_size);
        res.sub_assign(PairingsBn254.new_fr(1));
    }

    function verify_at_z(
        PartialVerifierState memory state,
        Proof memory proof,
        VerificationKey memory vk
    ) internal view returns (bool) {
        PairingsBn254.Fr memory lhs = evaluate_vanishing(vk.domain_size, state.z);
        require(lhs.value != 0); // we can not check a polynomial relationship if point `z` is in the domain
        lhs.mul_assign(proof.quotient_polynomial_at_z);

        PairingsBn254.Fr memory quotient_challenge = PairingsBn254.new_fr(1);
        PairingsBn254.Fr memory rhs = PairingsBn254.copy(proof.linearization_polynomial_at_z);

        // public inputs
        PairingsBn254.Fr memory tmp = PairingsBn254.new_fr(0);
        PairingsBn254.Fr memory inputs_term = PairingsBn254.new_fr(0);
        for (uint256 i = 0; i < proof.input_values.length; i++) {
            tmp.assign(state.cached_lagrange_evals[i]);
            tmp.mul_assign(PairingsBn254.new_fr(proof.input_values[i]));
            inputs_term.add_assign(tmp);
        }

        inputs_term.mul_assign(proof.gate_selector_values_at_z[0]);
        rhs.add_assign(inputs_term);

        // now we need 5th power
        quotient_challenge.mul_assign(state.alpha);
        quotient_challenge.mul_assign(state.alpha);
        quotient_challenge.mul_assign(state.alpha);
        quotient_challenge.mul_assign(state.alpha);
        quotient_challenge.mul_assign(state.alpha);

        PairingsBn254.Fr memory z_part = PairingsBn254.copy(proof.copy_grand_product_at_z_omega);
        for (uint256 i = 0; i < proof.permutation_polynomials_at_z.length; i++) {
            tmp.assign(proof.permutation_polynomials_at_z[i]);
            tmp.mul_assign(state.beta);
            tmp.add_assign(state.gamma);
            tmp.add_assign(proof.wire_values_at_z[i]);

            z_part.mul_assign(tmp);
        }

        tmp.assign(state.gamma);
        // we need a wire value of the last polynomial in enumeration
        tmp.add_assign(proof.wire_values_at_z[STATE_WIDTH - 1]);

        z_part.mul_assign(tmp);
        z_part.mul_assign(quotient_challenge);

        rhs.sub_assign(z_part);

        quotient_challenge.mul_assign(state.alpha);

        tmp.assign(state.cached_lagrange_evals[0]);
        tmp.mul_assign(quotient_challenge);

        rhs.sub_assign(tmp);

        return lhs.value == rhs.value;
    }

    function add_contribution_from_range_constraint_gates(
        PartialVerifierState memory state,
        Proof memory proof,
        PairingsBn254.Fr memory current_alpha
    ) internal pure returns (PairingsBn254.Fr memory res) {
        // now add contribution from range constraint gate
        // we multiply selector commitment by all the factors (alpha*(c - 4d)(c - 4d - 1)(..-2)(..-3) + alpha^2 * (4b - c)()()() + {} + {})

        PairingsBn254.Fr memory one_fr = PairingsBn254.new_fr(ONE);
        PairingsBn254.Fr memory two_fr = PairingsBn254.new_fr(TWO);
        PairingsBn254.Fr memory three_fr = PairingsBn254.new_fr(THREE);
        PairingsBn254.Fr memory four_fr = PairingsBn254.new_fr(FOUR);

        res = PairingsBn254.new_fr(0);
        PairingsBn254.Fr memory t0 = PairingsBn254.new_fr(0);
        PairingsBn254.Fr memory t1 = PairingsBn254.new_fr(0);
        PairingsBn254.Fr memory t2 = PairingsBn254.new_fr(0);

        for (uint256 i = 0; i < 3; i++) {
            current_alpha.mul_assign(state.alpha);

            // high - 4*low

            // this is 4*low
            t0 = PairingsBn254.copy(proof.wire_values_at_z[3 - i]);
            t0.mul_assign(four_fr);

            // high
            t1 = PairingsBn254.copy(proof.wire_values_at_z[2 - i]);
            t1.sub_assign(t0);

            // t0 is now t1 - {0,1,2,3}

            // first unroll manually for -0;
            t2 = PairingsBn254.copy(t1);

            // -1
            t0 = PairingsBn254.copy(t1);
            t0.sub_assign(one_fr);
            t2.mul_assign(t0);

            // -2
            t0 = PairingsBn254.copy(t1);
            t0.sub_assign(two_fr);
            t2.mul_assign(t0);

            // -3
            t0 = PairingsBn254.copy(t1);
            t0.sub_assign(three_fr);
            t2.mul_assign(t0);

            t2.mul_assign(current_alpha);

            res.add_assign(t2);
        }

        // now also d_next - 4a

        current_alpha.mul_assign(state.alpha);

        // high - 4*low

        // this is 4*low
        t0 = PairingsBn254.copy(proof.wire_values_at_z[0]);
        t0.mul_assign(four_fr);

        // high
        t1 = PairingsBn254.copy(proof.wire_values_at_z_omega[0]);
        t1.sub_assign(t0);

        // t0 is now t1 - {0,1,2,3}

        // first unroll manually for -0;
        t2 = PairingsBn254.copy(t1);

        // -1
        t0 = PairingsBn254.copy(t1);
        t0.sub_assign(one_fr);
        t2.mul_assign(t0);

        // -2
        t0 = PairingsBn254.copy(t1);
        t0.sub_assign(two_fr);
        t2.mul_assign(t0);

        // -3
        t0 = PairingsBn254.copy(t1);
        t0.sub_assign(three_fr);
        t2.mul_assign(t0);

        t2.mul_assign(current_alpha);

        res.add_assign(t2);

        return res;
    }

    function reconstruct_linearization_commitment(
        PartialVerifierState memory state,
        Proof memory proof,
        VerificationKey memory vk
    ) internal view returns (PairingsBn254.G1Point memory res) {
        // we compute what power of v is used as a delinearization factor in batch opening of
        // commitments. Let's label W(x) = 1 / (x - z) *
        // [
        // t_0(x) + z^n * t_1(x) + z^2n * t_2(x) + z^3n * t_3(x) - t(z)
        // + v (r(x) - r(z))
        // + v^{2..5} * (witness(x) - witness(z))
        // + v^{6} * (selector(x) - selector(z))
        // + v^{7..9} * (permutation(x) - permutation(z))
        // ]
        // W'(x) = 1 / (x - z*omega) *
        // [
        // + v^10 (z(x) - z(z*omega)) <- we need this power
        // + v^11 * (d(x) - d(z*omega))
        // ]
        //

        // we reconstruct linearization polynomial virtual selector
        // for that purpose we first linearize over main gate (over all it's selectors)
        // and multiply them by value(!) of the corresponding main gate selector
        res = PairingsBn254.copy_g1(vk.gate_setup_commitments[STATE_WIDTH + 1]); // index of q_const(x)

        PairingsBn254.G1Point memory tmp_g1 = PairingsBn254.P1();
        PairingsBn254.Fr memory tmp_fr = PairingsBn254.new_fr(0);

        // addition gates
        for (uint256 i = 0; i < STATE_WIDTH; i++) {
            tmp_g1 = vk.gate_setup_commitments[i].point_mul(proof.wire_values_at_z[i]);
            res.point_add_assign(tmp_g1);
        }

        // multiplication gate
        tmp_fr.assign(proof.wire_values_at_z[0]);
        tmp_fr.mul_assign(proof.wire_values_at_z[1]);
        tmp_g1 = vk.gate_setup_commitments[STATE_WIDTH].point_mul(tmp_fr);
        res.point_add_assign(tmp_g1);

        // d_next
        tmp_g1 = vk.gate_setup_commitments[STATE_WIDTH+2].point_mul(proof.wire_values_at_z_omega[0]); // index of q_d_next(x)
        res.point_add_assign(tmp_g1);

        // multiply by main gate selector(z)
        res.point_mul_assign(proof.gate_selector_values_at_z[0]); // these is only one explicitly opened selector

        PairingsBn254.Fr memory current_alpha = PairingsBn254.new_fr(ONE);

        // calculate scalar contribution from the range check gate
        tmp_fr = add_contribution_from_range_constraint_gates(state, proof, current_alpha);
        tmp_g1 = vk.gate_selector_commitments[1].point_mul(tmp_fr); // selector commitment for range constraint gate * scalar
        res.point_add_assign(tmp_g1);

        // proceed as normal to copy permutation
        current_alpha.mul_assign(state.alpha); // alpha^5

        PairingsBn254.Fr memory alpha_for_grand_product = PairingsBn254.copy(current_alpha);

        // z * non_res * beta + gamma + a
        PairingsBn254.Fr memory grand_product_part_at_z = PairingsBn254.copy(state.z);
        grand_product_part_at_z.mul_assign(state.beta);
        grand_product_part_at_z.add_assign(proof.wire_values_at_z[0]);
        grand_product_part_at_z.add_assign(state.gamma);
        for (uint256 i = 0; i < vk.copy_permutation_non_residues.length; i++) {
            tmp_fr.assign(state.z);
            tmp_fr.mul_assign(vk.copy_permutation_non_residues[i]);
            tmp_fr.mul_assign(state.beta);
            tmp_fr.add_assign(state.gamma);
            tmp_fr.add_assign(proof.wire_values_at_z[i+1]);

            grand_product_part_at_z.mul_assign(tmp_fr);
        }

        grand_product_part_at_z.mul_assign(alpha_for_grand_product);

        // alpha^n & L_{0}(z), and we bump current_alpha
        current_alpha.mul_assign(state.alpha);

        tmp_fr.assign(state.cached_lagrange_evals[0]);
        tmp_fr.mul_assign(current_alpha);

        grand_product_part_at_z.add_assign(tmp_fr);

        // prefactor for grand_product(x) is complete

        // add to the linearization a part from the term
        // - (a(z) + beta*perm_a + gamma)*()*()*z(z*omega) * beta * perm_d(X)
        PairingsBn254.Fr memory last_permutation_part_at_z = PairingsBn254.new_fr(1);
        for (uint256 i = 0; i < proof.permutation_polynomials_at_z.length; i++) {
            tmp_fr.assign(state.beta);
            tmp_fr.mul_assign(proof.permutation_polynomials_at_z[i]);
            tmp_fr.add_assign(state.gamma);
            tmp_fr.add_assign(proof.wire_values_at_z[i]);

            last_permutation_part_at_z.mul_assign(tmp_fr);
        }

        last_permutation_part_at_z.mul_assign(state.beta);
        last_permutation_part_at_z.mul_assign(proof.copy_grand_product_at_z_omega);
        last_permutation_part_at_z.mul_assign(alpha_for_grand_product); // we multiply by the power of alpha from the argument

        // actually multiply prefactors by z(x) and perm_d(x) and combine them
        tmp_g1 = proof.copy_permutation_grand_product_commitment.point_mul(grand_product_part_at_z);
        tmp_g1.point_sub_assign(vk.copy_permutation_commitments[STATE_WIDTH - 1].point_mul(last_permutation_part_at_z));

        res.point_add_assign(tmp_g1);
        // multiply them by v immedately as linearization has a factor of v^1
        res.point_mul_assign(state.v);
        // res now contains contribution from the gates linearization and
        // copy permutation part

        // now we need to add a part that is the rest
        // for z(x*omega):
        // - (a(z) + beta*perm_a + gamma)*()*()*(d(z) + gamma) * z(x*omega)
    }

    function aggregate_commitments(
        PartialVerifierState memory state,
        Proof memory proof,
        VerificationKey memory vk
    ) internal view returns (PairingsBn254.G1Point[2] memory res) {
        PairingsBn254.G1Point memory d = reconstruct_linearization_commitment(state, proof, vk);

        PairingsBn254.Fr memory z_in_domain_size = state.z.pow(vk.domain_size);

        PairingsBn254.G1Point memory tmp_g1 = PairingsBn254.P1();

        PairingsBn254.Fr memory aggregation_challenge = PairingsBn254.new_fr(1);

        PairingsBn254.G1Point memory commitment_aggregation = PairingsBn254.copy_g1(proof.quotient_poly_commitments[0]);
        PairingsBn254.Fr memory tmp_fr = PairingsBn254.new_fr(1);
        for (uint i = 1; i < proof.quotient_poly_commitments.length; i++) {
            tmp_fr.mul_assign(z_in_domain_size);
            tmp_g1 = proof.quotient_poly_commitments[i].point_mul(tmp_fr);
            commitment_aggregation.point_add_assign(tmp_g1);
        }

        aggregation_challenge.mul_assign(state.v);
        commitment_aggregation.point_add_assign(d);

        for (uint i = 0; i < proof.wire_commitments.length; i++) {
            aggregation_challenge.mul_assign(state.v);
            tmp_g1 = proof.wire_commitments[i].point_mul(aggregation_challenge);
            commitment_aggregation.point_add_assign(tmp_g1);
        }

        for (uint i = 0; i < NUM_GATE_SELECTORS_OPENED_EXPLICITLY; i++) {
            aggregation_challenge.mul_assign(state.v);
            tmp_g1 = vk.gate_selector_commitments[0].point_mul(aggregation_challenge);
            commitment_aggregation.point_add_assign(tmp_g1);
        }

        for (uint i = 0; i < vk.copy_permutation_commitments.length - 1; i++) {
            aggregation_challenge.mul_assign(state.v);
            tmp_g1 = vk.copy_permutation_commitments[i].point_mul(aggregation_challenge);
            commitment_aggregation.point_add_assign(tmp_g1);
        }

        aggregation_challenge.mul_assign(state.v);
        // now do prefactor for grand_product(x*omega)
        tmp_fr.assign(aggregation_challenge);
        tmp_fr.mul_assign(state.u);
        commitment_aggregation.point_add_assign(proof.copy_permutation_grand_product_commitment.point_mul(tmp_fr));

        aggregation_challenge.mul_assign(state.v);

        tmp_fr.assign(aggregation_challenge);
        tmp_fr.mul_assign(state.u);
        tmp_g1 = proof.wire_commitments[STATE_WIDTH - 1].point_mul(tmp_fr);
        commitment_aggregation.point_add_assign(tmp_g1);

        // collect opening values
        aggregation_challenge = PairingsBn254.new_fr(1);

        PairingsBn254.Fr memory aggregated_value = PairingsBn254.copy(proof.quotient_polynomial_at_z);

        aggregation_challenge.mul_assign(state.v);

        tmp_fr.assign(proof.linearization_polynomial_at_z);
        tmp_fr.mul_assign(aggregation_challenge);
        aggregated_value.add_assign(tmp_fr);

        for (uint i = 0; i < proof.wire_values_at_z.length; i++) {
            aggregation_challenge.mul_assign(state.v);

            tmp_fr.assign(proof.wire_values_at_z[i]);
            tmp_fr.mul_assign(aggregation_challenge);
            aggregated_value.add_assign(tmp_fr);
        }

        for (uint i = 0; i < proof.gate_selector_values_at_z.length; i++) {
            aggregation_challenge.mul_assign(state.v);
            tmp_fr.assign(proof.gate_selector_values_at_z[i]);
            tmp_fr.mul_assign(aggregation_challenge);
            aggregated_value.add_assign(tmp_fr);
        }

        for (uint i = 0; i < proof.permutation_polynomials_at_z.length; i++) {
            aggregation_challenge.mul_assign(state.v);

            tmp_fr.assign(proof.permutation_polynomials_at_z[i]);
            tmp_fr.mul_assign(aggregation_challenge);
            aggregated_value.add_assign(tmp_fr);
        }

        aggregation_challenge.mul_assign(state.v);

        tmp_fr.assign(proof.copy_grand_product_at_z_omega);
        tmp_fr.mul_assign(aggregation_challenge);
        tmp_fr.mul_assign(state.u);
        aggregated_value.add_assign(tmp_fr);

        aggregation_challenge.mul_assign(state.v);

        tmp_fr.assign(proof.wire_values_at_z_omega[0]);
        tmp_fr.mul_assign(aggregation_challenge);
        tmp_fr.mul_assign(state.u);
        aggregated_value.add_assign(tmp_fr);

        commitment_aggregation.point_sub_assign(PairingsBn254.P1().point_mul(aggregated_value));

        PairingsBn254.G1Point memory pair_with_generator = commitment_aggregation;
        pair_with_generator.point_add_assign(proof.opening_at_z_proof.point_mul(state.z));

        tmp_fr.assign(state.z);
        tmp_fr.mul_assign(vk.omega);
        tmp_fr.mul_assign(state.u);
        pair_with_generator.point_add_assign(proof.opening_at_z_omega_proof.point_mul(tmp_fr));

        PairingsBn254.G1Point memory pair_with_x = proof.opening_at_z_omega_proof.point_mul(state.u);
        pair_with_x.point_add_assign(proof.opening_at_z_proof);
        pair_with_x.negate();

        res[0] = pair_with_generator;
        res[1] = pair_with_x;

        return res;
    }

    function verify_initial(
        PartialVerifierState memory state,
        Proof memory proof,
        VerificationKey memory vk
    ) internal view returns (bool) {
        require(proof.input_values.length == vk.num_inputs);
        require(vk.num_inputs >= 1);
        TranscriptLibrary.Transcript memory transcript = TranscriptLibrary.new_transcript();
        for (uint256 i = 0; i < vk.num_inputs; i++) {
            transcript.update_with_u256(proof.input_values[i]);
        }

        for (uint256 i = 0; i < proof.wire_commitments.length; i++) {
            transcript.update_with_g1(proof.wire_commitments[i]);
        }

        state.beta = transcript.get_challenge();
        state.gamma = transcript.get_challenge();

        transcript.update_with_g1(proof.copy_permutation_grand_product_commitment);
        state.alpha = transcript.get_challenge();

        for (uint256 i = 0; i < proof.quotient_poly_commitments.length; i++) {
            transcript.update_with_g1(proof.quotient_poly_commitments[i]);
        }

        state.z = transcript.get_challenge();

        uint256[] memory lagrange_poly_numbers = new uint256[](vk.num_inputs);
        for (uint256 i = 0; i < lagrange_poly_numbers.length; i++) {
            lagrange_poly_numbers[i] = i;
        }

        state.cached_lagrange_evals = batch_evaluate_lagrange_poly_out_of_domain(
            lagrange_poly_numbers,
            vk.domain_size,
            vk.omega, state.z
        );

        bool valid = verify_at_z(state, proof, vk);

        if (valid == false) {
            return false;
        }

        transcript.update_with_fr(proof.quotient_polynomial_at_z);

        for (uint256 i = 0; i < proof.wire_values_at_z.length; i++) {
            transcript.update_with_fr(proof.wire_values_at_z[i]);
        }

        for (uint256 i = 0; i < proof.wire_values_at_z_omega.length; i++) {
            transcript.update_with_fr(proof.wire_values_at_z_omega[i]);
        }

        transcript.update_with_fr(proof.gate_selector_values_at_z[0]);

        for (uint256 i = 0; i < proof.permutation_polynomials_at_z.length; i++) {
            transcript.update_with_fr(proof.permutation_polynomials_at_z[i]);
        }

        transcript.update_with_fr(proof.copy_grand_product_at_z_omega);
        transcript.update_with_fr(proof.linearization_polynomial_at_z);

        state.v = transcript.get_challenge();
        transcript.update_with_g1(proof.opening_at_z_proof);
        transcript.update_with_g1(proof.opening_at_z_omega_proof);
        state.u = transcript.get_challenge();

        return true;
    }

    // This verifier is for a PLONK with a state width 4
    // and main gate equation
    // q_a(X) * a(X) +
    // q_b(X) * b(X) +
    // q_c(X) * c(X) +
    // q_d(X) * d(X) +
    // q_m(X) * a(X) * b(X) +
    // q_constants(X)+
    // q_d_next(X) * d(X*omega)
    // where q_{}(X) are selectors a, b, c, d - state (witness) polynomials
    // q_d_next(X) "peeks" into the next row of the trace, so it takes
    // the same d(X) polynomial, but shifted

    function aggregate_for_verification(Proof memory proof, VerificationKey memory vk) internal view returns (bool valid, PairingsBn254.G1Point[2] memory part) {
        PartialVerifierState memory state;

        valid = verify_initial(state, proof, vk);

        if (valid == false) {
            return (valid, part);
        }

        part = aggregate_commitments(state, proof, vk);

        (valid, part);
    }

    function verify(Proof memory proof, VerificationKey memory vk) internal view returns (bool) {
        (bool valid, PairingsBn254.G1Point[2] memory recursive_proof_part) = aggregate_for_verification(proof, vk);
        if (valid == false) {
            return false;
        }

        valid = PairingsBn254.pairingProd2(recursive_proof_part[0], PairingsBn254.P2(), recursive_proof_part[1], vk.g2_x);

        return valid;
    }

    function verify_recursive(
        Proof memory proof,
        VerificationKey memory vk,
        uint256 recursive_vks_root,
        uint8 max_valid_index,
        uint8[] memory recursive_vks_indexes,
        uint256[] memory individual_vks_inputs,
        uint256[] memory subproofs_limbs
    ) internal view returns (bool) {
        (uint256 recursive_input, PairingsBn254.G1Point[2] memory aggregated_g1s) = reconstruct_recursive_public_input(
            recursive_vks_root, max_valid_index, recursive_vks_indexes,
            individual_vks_inputs, subproofs_limbs
        );

        assert(recursive_input == proof.input_values[0]);

        (bool valid, PairingsBn254.G1Point[2] memory recursive_proof_part) = aggregate_for_verification(proof, vk);
        if (valid == false) {
            return false;
        }

        recursive_proof_part[0].point_add_assign(aggregated_g1s[0]);
        recursive_proof_part[1].point_add_assign(aggregated_g1s[1]);

        valid = PairingsBn254.pairingProd2(recursive_proof_part[0], PairingsBn254.P2(), recursive_proof_part[1], vk.g2_x);

        return valid;
    }

    function reconstruct_recursive_public_input(
        uint256 recursive_vks_root,
        uint8 max_valid_index,
        uint8[] memory recursive_vks_indexes,
        uint256[] memory individual_vks_inputs,
        uint256[] memory subproofs_aggregated
    ) internal pure returns (uint256 recursive_input, PairingsBn254.G1Point[2] memory reconstructed_g1s) {
        assert(recursive_vks_indexes.length == individual_vks_inputs.length);
        bytes memory concatenated = abi.encodePacked(recursive_vks_root);
        uint8 index;
        for (uint256 i = 0; i < recursive_vks_indexes.length; i++) {
            index = recursive_vks_indexes[i];
            assert(index <= max_valid_index);
            concatenated = abi.encodePacked(concatenated, index);
        }
        uint256 input;
        for (uint256 i = 0; i < recursive_vks_indexes.length; i++) {
            input = individual_vks_inputs[i];
            //            assert(input < PairingsBn254.r_mod);
            concatenated = abi.encodePacked(concatenated, input);
        }

        concatenated = abi.encodePacked(concatenated, subproofs_aggregated);

        bytes32 commitment = sha256(concatenated);
        recursive_input = uint256(commitment) & RECURSIVE_CIRCUIT_INPUT_COMMITMENT_MASK;

        reconstructed_g1s[0] = PairingsBn254.new_g1_checked(
            subproofs_aggregated[0] + (subproofs_aggregated[1] << LIMB_WIDTH) + (subproofs_aggregated[2] << 2*LIMB_WIDTH) + (subproofs_aggregated[3] << 3*LIMB_WIDTH),
            subproofs_aggregated[4] + (subproofs_aggregated[5] << LIMB_WIDTH) + (subproofs_aggregated[6] << 2*LIMB_WIDTH) + (subproofs_aggregated[7] << 3*LIMB_WIDTH)
        );

        reconstructed_g1s[1] = PairingsBn254.new_g1_checked(
            subproofs_aggregated[8] + (subproofs_aggregated[9] << LIMB_WIDTH) + (subproofs_aggregated[10] << 2*LIMB_WIDTH) + (subproofs_aggregated[11] << 3*LIMB_WIDTH),
            subproofs_aggregated[12] + (subproofs_aggregated[13] << LIMB_WIDTH) + (subproofs_aggregated[14] << 2*LIMB_WIDTH) + (subproofs_aggregated[15] << 3*LIMB_WIDTH)
        );

        return (recursive_input, reconstructed_g1s);
    }
}

contract AggVerifierWithDeserialize is Plonk4AggVerifierWithAccessToDNext {
    uint256 constant SERIALIZED_PROOF_LENGTH = 34;

    function deserialize_proof(
        uint256[] memory public_inputs,
        uint256[] memory serialized_proof
    ) internal pure returns(Proof memory proof) {
        require(serialized_proof.length == SERIALIZED_PROOF_LENGTH);
        proof.input_values = new uint256[](public_inputs.length);
        for (uint256 i = 0; i < public_inputs.length; i++) {
            proof.input_values[i] = public_inputs[i];
        }

        uint256 j = 0;
        for (uint256 i = 0; i < STATE_WIDTH; i++) {
            proof.wire_commitments[i] = PairingsBn254.new_g1_checked(
                serialized_proof[j],
                serialized_proof[j+1]
            );

            j += 2;
        }

        proof.copy_permutation_grand_product_commitment = PairingsBn254.new_g1_checked(
            serialized_proof[j],
            serialized_proof[j+1]
        );
        j += 2;

        for (uint256 i = 0; i < STATE_WIDTH; i++) {
            proof.quotient_poly_commitments[i] = PairingsBn254.new_g1_checked(
                serialized_proof[j],
                serialized_proof[j+1]
            );

            j += 2;
        }

        for (uint256 i = 0; i < STATE_WIDTH; i++) {
            proof.wire_values_at_z[i] = PairingsBn254.new_fr(
                serialized_proof[j]
            );

            j += 1;
        }

        for (uint256 i = 0; i < proof.wire_values_at_z_omega.length; i++) {
            proof.wire_values_at_z_omega[i] = PairingsBn254.new_fr(
                serialized_proof[j]
            );

            j += 1;
        }

        for (uint256 i = 0; i < proof.gate_selector_values_at_z.length; i++) {
            proof.gate_selector_values_at_z[i] = PairingsBn254.new_fr(
                serialized_proof[j]
            );

            j += 1;
        }

        for (uint256 i = 0; i < proof.permutation_polynomials_at_z.length; i++) {
            proof.permutation_polynomials_at_z[i] = PairingsBn254.new_fr(
                serialized_proof[j]
            );

            j += 1;
        }


        proof.copy_grand_product_at_z_omega = PairingsBn254.new_fr(
            serialized_proof[j]
        );

        j += 1;

        proof.quotient_polynomial_at_z = PairingsBn254.new_fr(
            serialized_proof[j]
        );

        j += 1;

        proof.linearization_polynomial_at_z = PairingsBn254.new_fr(
            serialized_proof[j]
        );

        j += 1;

        proof.opening_at_z_proof = PairingsBn254.new_g1_checked(
            serialized_proof[j],
            serialized_proof[j+1]
        );
        j += 2;

        proof.opening_at_z_omega_proof = PairingsBn254.new_g1_checked(
            serialized_proof[j],
            serialized_proof[j+1]
        );
    }

    function verify_serialized_proof(
        uint256[] memory public_inputs,
        uint256[] memory serialized_proof,
        VerificationKey memory vk
    ) public view returns (bool) {
        require(vk.num_inputs == public_inputs.length);

        Proof memory proof = deserialize_proof(public_inputs, serialized_proof);

        bool valid = verify(proof, vk);

        return valid;
    }

    function verify_serialized_proof_with_recursion(
        uint256[] memory public_inputs,
        uint256[] memory serialized_proof,
        uint256 recursive_vks_root,
        uint8 max_valid_index,
        uint8[] memory recursive_vks_indexes,
        uint256[] memory individual_vks_inputs,
        uint256[] memory subproofs_limbs,
        VerificationKey memory vk
    ) public view returns (bool) {
        require(vk.num_inputs == public_inputs.length);

        Proof memory proof = deserialize_proof(public_inputs, serialized_proof);

        bool valid = verify_recursive(proof, vk, recursive_vks_root, max_valid_index, recursive_vks_indexes, individual_vks_inputs, subproofs_limbs);

        return valid;
    }
}
