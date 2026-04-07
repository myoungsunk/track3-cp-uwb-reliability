function test_extract_rcp
% TEST_EXTRACT_RCP Validate extract_rcp and extract_afp using synthetic CIR cases.
fs_hz = 2e9;
n_samples = 4096;
base_idx = 900;
rng(42);

t_axis_ns = ((0:n_samples-1) / fs_hz) * 1e9;

params = struct();
params.fp_threshold_ratio = 0.2;
params.T_w = 2.0;
params.min_power_dbm = -150;
params.r_CP_clip = 1e4;

% 1) Pure LoS: RHCP >> LHCP.
cir_r_los = synthetic_cir(n_samples, base_idx, 1.0, 0.10, 0.8, 1e-4);
cir_l_los = synthetic_cir(n_samples, base_idx, 0.10, 0.08, 0.9, 1e-4);
[r_cp_los, info_los] = extract_rcp(cir_r_los, cir_l_los, params);
assert(isfinite(r_cp_los) && r_cp_los > 20, 'Pure LoS should yield r_CP >> 1.');
assert(info_los.flag == "ok" || info_los.flag == "clipped", 'Unexpected flag for LoS case.');

% 2) Single-bounce NLoS-like: LHCP > RHCP.
cir_r_nlos = synthetic_cir(n_samples, base_idx, 0.20, 0.40, 0.7, 1e-4);
cir_l_nlos = synthetic_cir(n_samples, base_idx, 0.80, 0.30, 0.7, 1e-4);
r_cp_nlos = extract_rcp(cir_r_nlos, cir_l_nlos, params);
assert(isfinite(r_cp_nlos) && r_cp_nlos < 1.0, 'NLoS-like case should yield r_CP < 1.');

% 3) Equal power.
cir_r_eq = synthetic_cir(n_samples, base_idx, 0.60, 0.20, 0.8, 1e-4);
cir_l_eq = synthetic_cir(n_samples, base_idx, 0.60, 0.20, 0.8, 1e-4);
r_cp_eq = extract_rcp(cir_r_eq, cir_l_eq, params);
assert(isfinite(r_cp_eq) && abs(r_cp_eq - 1.0) < 0.25, 'Equal-power case should yield r_CP ~= 1.');

% 4) LoS-like concentration test for a_FP (RHCP source).
params.afp_cir_source = 'RHCP';
cir_sharp = synthetic_cir(n_samples, base_idx, 1.0, 0.02, 1.5, 1e-6);
a_fp_sharp = extract_afp(cir_sharp, cir_l_los, t_axis_ns, params);
assert(a_fp_sharp > 0.85, 'LoS-like sharp CIR should yield a_FP close to 1.');

fprintf('test_extract_rcp passed.\n');
end

function cir = synthetic_cir(n_samples, peak_idx, main_amp, multipath_scale, decay, noise_sigma)
% SYNTHETIC_CIR Generate synthetic complex CIR: Gaussian pulse with multipath tail.
sample_idx = (1:n_samples).';
pulse_sigma = 2.0;

main_phase = 2 * pi * rand();
cir = main_amp * exp(-0.5 * ((sample_idx - peak_idx) / pulse_sigma) .^ 2) * exp(1j * main_phase);

n_paths = 8;
for path_idx = 1:n_paths
    delay_samples = peak_idx + path_idx * (8 + randi([0, 4]));
    if delay_samples > n_samples
        continue;
    end
    path_amp = multipath_scale * main_amp * exp(-decay * path_idx);
    path_phase = 2 * pi * rand();
    cir = cir + path_amp * exp(-0.5 * ((sample_idx - delay_samples) / (pulse_sigma + 1)) .^ 2) * exp(1j * path_phase);
end

cir = cir + noise_sigma * (randn(n_samples, 1) + 1j * randn(n_samples, 1));
end
