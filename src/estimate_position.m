function [pos_est, pos_info] = estimate_position(sim_data_test, lut, params)
% ESTIMATE_POSITION Estimate 2D position from RSSD-based DoA and first-path ranging.
if nargin < 3
    params = struct();
end
if ~isstruct(sim_data_test)
    error('[estimate_position] sim_data_test must be a struct.');
end

required_fields = {'CIR_rx1', 'CIR_rx2', 't_axis', 'RSS_rx1', 'RSS_rx2'};
for idx = 1:numel(required_fields)
    if ~isfield(sim_data_test, required_fields{idx})
        error('[estimate_position] sim_data_test.%s is required.', required_fields{idx});
    end
end

rssd_measured = double(sim_data_test.RSS_rx1(:)) - double(sim_data_test.RSS_rx2(:));
[doa_est, doa_info] = estimate_doa_rssd(rssd_measured, lut, params);

n_pos = numel(doa_est);
t_axis_ns = double(sim_data_test.t_axis(:));
if isempty(t_axis_ns)
    error('[estimate_position] sim_data_test.t_axis must be non-empty.');
end

range_channel = upper(string(get_param(params, 'range_channel', 'RHCP')));
c0 = get_param(params, 'c0', 299792458);
if ~isfinite(c0) || c0 <= 0
    error('[estimate_position] params.c0 must be positive finite scalar.');
end

range_est = nan(n_pos, 1);
fp_idx = nan(n_pos, 1);

for idx = 1:n_pos
    if range_channel == "LHCP"
        cir_range = sim_data_test.CIR_rx2(idx, :).';
    else
        cir_range = sim_data_test.CIR_rx1(idx, :).';
    end

    params_fp = params;
    params_fp.t_axis = t_axis_ns;
    [fp_idx_i, ~] = detect_first_path(abs(cir_range), params_fp);

    fp_idx(idx) = double(fp_idx_i);
    if isnan(fp_idx_i)
        continue;
    end

    t_fp_ns = t_axis_ns(fp_idx_i);
    % TODO: spec 확인 필요 - single-sided vs round-trip 정의 최종 확정 필요.
    range_est(idx) = t_fp_ns * 1e-9 * c0 / 2;
end

anchor_x_m = get_param(params, 'anchor_x_m', 0.0);
anchor_y_m = get_param(params, 'anchor_y_m', 0.0);
doa_reference_deg = get_param(params, 'doa_reference_deg', 0.0);

ang_rad = deg2rad(doa_est + doa_reference_deg);
x_est = anchor_x_m + range_est .* cos(ang_rad);
y_est = anchor_y_m + range_est .* sin(ang_rad);

if isfield(sim_data_test, 'pos_id') && numel(sim_data_test.pos_id) == n_pos
    pos_id = uint32(sim_data_test.pos_id(:));
else
    pos_id = uint32((1:n_pos)');
end

if isfield(sim_data_test, 'x_coord_m') && isfield(sim_data_test, 'y_coord_m') && ...
        numel(sim_data_test.x_coord_m) == n_pos && numel(sim_data_test.y_coord_m) == n_pos
    gt_x = double(sim_data_test.x_coord_m(:));
    gt_y = double(sim_data_test.y_coord_m(:));

    range_true = sqrt((gt_x - anchor_x_m).^2 + (gt_y - anchor_y_m).^2);
    doa_true = atan2d(gt_y - anchor_y_m, gt_x - anchor_x_m) - doa_reference_deg;

    range_error = abs(range_est - range_true);
    doa_error = abs(wrap_to_180(doa_est - doa_true));
    pos_error = sqrt((x_est - gt_x).^2 + (y_est - gt_y).^2);
else
    range_error = nan(n_pos, 1);
    doa_error = nan(n_pos, 1);
    pos_error = nan(n_pos, 1);
end

pos_est = table( ...
    pos_id, ...
    doa_est, ...
    range_est, ...
    x_est, ...
    y_est, ...
    doa_error, ...
    range_error, ...
    pos_error, ...
    doa_info.ambiguity_flag, ...
    fp_idx, ...
    'VariableNames', {'pos_id', 'doa_est', 'range_est', 'x_est', 'y_est', 'doa_error', 'range_error', 'pos_error', 'ambiguity_flag', 'fp_idx'});

pos_info = struct();
pos_info.lut_used = lut;
pos_info.doa_info = doa_info;
pos_info.fp_idx = fp_idx;
end

function value = wrap_to_180(value)
value = mod(value + 180, 360) - 180;
end
