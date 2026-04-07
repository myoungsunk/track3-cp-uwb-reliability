function test_detect_first_path
% TEST_DETECT_FIRST_PATH Validate first-path detector behavior and edge cases.

params = struct('fp_threshold_ratio', 0.2);

% 1) Single delta peak.
cir1 = zeros(256, 1);
cir1(80) = 1.0;
[idx1, info1] = detect_first_path(cir1, params);
assert(idx1 == 80, 'Single-peak case should return exact peak index.');
assert(info1.found == true, 'Single-peak case should be found.');

% 2) Multi-peak with small early leading edge.
cir2 = zeros(300, 1);
cir2(100) = 0.20;
cir2(150) = 1.00;
[idx2, ~] = detect_first_path(cir2, params);
assert(idx2 == 100, 'Leading-edge should identify first threshold crossing.');

% 3) Search-window support.
t_axis_ns = (0:299)';
cir3 = zeros(300, 1);
cir3(51) = 1.0;   % outside requested window
cir3(201) = 0.9;  % inside requested window
params3 = struct('fp_threshold_ratio', 0.2, 'fp_search_window_ns', [150, 250], 't_axis', t_axis_ns);
[idx3, info3] = detect_first_path(cir3, params3);
assert(idx3 >= 150 && idx3 <= 250, 'Search window should ignore out-of-window peaks.');
assert(info3.search_range(1) >= 150 && info3.search_range(2) <= 251, 'Search range should map to requested window.');

% 4) All zeros.
cir4 = zeros(128, 1);
[idx4, info4] = detect_first_path(cir4, params);
assert(isnan(idx4), 'All-zero case should return NaN.');
assert(info4.found == false, 'All-zero case should be marked as not found.');

fprintf('test_detect_first_path passed.\n');
end
