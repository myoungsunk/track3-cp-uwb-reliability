function test_build_sim_data
% TEST_BUILD_SIM_DATA Validate IFFT construction and window effects.

% Common params.
params = struct();
params.freq_range_ghz = [6.0, 7.0];
params.zeropad_factor = 4;
params.window_type = 'hanning';
params.data_role = 'test';
params.case_label_map = containers.Map({'caseA'}, {true});

% Synthetic grid for one position.
n_freq = 64;
freq_ghz = linspace(6.0, 7.0, n_freq).';
x_coord_mm = repmat(750, n_freq, 1);
y_coord_mm = repmat(-1250, n_freq, 1);
group_id = uint32(ones(n_freq, 1));
pol_type = repmat("CP", n_freq, 1);
case_id = repmat("caseA", n_freq, 1);

% 1) Single tone.
s21_tone = exp(1j * 2 * pi * (0:n_freq-1)' / n_freq);
freq_table1 = table(x_coord_mm, y_coord_mm, freq_ghz, s21_tone, s21_tone, group_id, pol_type, case_id, ...
    'VariableNames', {'x_coord_mm','y_coord_mm','freq_ghz','S21_rx1','S21_rx2','group_id','pol_type','case_id'});
sim1 = build_sim_data_from_table(freq_table1, params);
assert(size(sim1.CIR_rx1, 1) == 1, 'Single-position tone should create one CIR row.');
assert(size(sim1.CIR_rx1, 2) == n_freq * params.zeropad_factor, 'N_fft mismatch for single tone.');
assert(any(abs(sim1.CIR_rx1(1, :)) > 0), 'CIR should not be identically zero.');

% 2) Two tones should produce two dominant peaks in magnitude domain.
s21_two = exp(1j * 2 * pi * (0:n_freq-1)' / n_freq) + 0.8 * exp(1j * 2 * pi * 5 * (0:n_freq-1)' / n_freq);
freq_table2 = freq_table1;
freq_table2.S21_rx1 = s21_two;
freq_table2.S21_rx2 = s21_two;
sim2 = build_sim_data_from_table(freq_table2, params);
mag2 = abs(sim2.CIR_rx1(1, :));
[~, idx_sort] = sort(mag2, 'descend');
peak_ref = double(idx_sort(1));
peak_far = abs(double(idx_sort(2:10)) - peak_ref);
assert(any(peak_far > 3), 'Two-tone case should show at least two separated dominant peaks.');

% 3) Hanning window should suppress sidelobe level vs no-window baseline.
s21_flat = ones(n_freq, 1);
freq_table3 = freq_table1;
freq_table3.S21_rx1 = s21_flat;
freq_table3.S21_rx2 = s21_flat;
sim_win = build_sim_data_from_table(freq_table3, params);

n_fft = n_freq * params.zeropad_factor;
cir_nowin = ifft([s21_flat; zeros(n_fft - n_freq, 1)], n_fft);

mag_win = abs(sim_win.CIR_rx1(1, :)).';
mag_nowin = abs(cir_nowin);

[~, peak_win] = max(mag_win);
[~, peak_nowin] = max(mag_nowin);

mask_win = true(n_fft, 1);
mask_nowin = true(n_fft, 1);
mask_win(max(1, peak_win-2):min(n_fft, peak_win+2)) = false;
mask_nowin(max(1, peak_nowin-2):min(n_fft, peak_nowin+2)) = false;

sidelobe_max_win = max(mag_win(mask_win));
sidelobe_max_nowin = max(mag_nowin(mask_nowin));
assert(sidelobe_max_win < sidelobe_max_nowin, 'Hanning window should reduce sidelobe peak level.');

fprintf('test_build_sim_data passed.\n');
end
