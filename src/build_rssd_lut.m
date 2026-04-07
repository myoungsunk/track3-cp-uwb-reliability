function lut = build_rssd_lut(sim_data_guide, params)
% BUILD_RSSD_LUT Build RSSD-to-angle lookup table from guide data with incidence angles.
if nargin < 2
    params = struct();
end
if ~isstruct(sim_data_guide)
    error('[build_rssd_lut] sim_data_guide must be a struct.');
end
if ~isfield(sim_data_guide, 'inc_ang')
    error('[build_rssd_lut] sim_data_guide.inc_ang is required.');
end

inc_ang = double(sim_data_guide.inc_ang(:));
if ~isfield(sim_data_guide, 'RSS_rx1') || ~isfield(sim_data_guide, 'RSS_rx2')
    error('[build_rssd_lut] sim_data_guide must contain RSS_rx1 and RSS_rx2.');
end

antenna_pair = get_param(params, 'rssd_antenna_pair', [1, 2]);
if numel(antenna_pair) ~= 2
    error('[build_rssd_lut] params.rssd_antenna_pair must have length 2.');
end

rss_ant1 = get_rss_by_index(sim_data_guide, antenna_pair(1));
rss_ant2 = get_rss_by_index(sim_data_guide, antenna_pair(2));

valid_mask = isfinite(inc_ang) & isfinite(rss_ant1) & isfinite(rss_ant2);
inc_ang = inc_ang(valid_mask);
rss_ant1 = rss_ant1(valid_mask);
rss_ant2 = rss_ant2(valid_mask);
if numel(inc_ang) < 3
    error('[build_rssd_lut] At least 3 valid guide samples are required.');
end

rssd_raw = rss_ant1 - rss_ant2;

[ang_sorted, sort_idx] = sort(inc_ang, 'ascend');
rssd_sorted = rssd_raw(sort_idx);

[ang_unique, ~, grp_idx] = unique(ang_sorted, 'stable');
rssd_unique = accumarray(grp_idx, rssd_sorted, [], @mean);
if numel(ang_unique) < 3
    error('[build_rssd_lut] Unique guide angles are insufficient.');
end

interp_method = lower(string(get_param(params, 'rssd_interp_method', 'pchip')));
if interp_method ~= "pchip" && interp_method ~= "linear" && interp_method ~= "spline"
    error('[build_rssd_lut] params.rssd_interp_method must be pchip/linear/spline.');
end

lut_ang_step = get_param(params, 'lut_ang_step', 0.1);
if ~isfinite(lut_ang_step) || lut_ang_step <= 0
    error('[build_rssd_lut] params.lut_ang_step must be positive finite scalar.');
end

ang_axis = (ang_unique(1):lut_ang_step:ang_unique(end)).';
interp_obj = griddedInterpolant(ang_unique, rssd_unique, char(interp_method), 'nearest');
rssd_curve = interp_obj(ang_axis);

monotonic_range = detect_monotonic_range(ang_axis, rssd_curve);

lut = struct();
lut.ang_axis = ang_axis;
lut.rssd_curve = rssd_curve;
lut.rssd_raw = rssd_unique;
lut.ang_raw = ang_unique;
lut.interp_obj = interp_obj;
lut.monotonic_range = monotonic_range;
lut.params = params;
end

function rss = get_rss_by_index(sim_data, idx)
if idx == 1
    rss = double(sim_data.RSS_rx1(:));
elseif idx == 2
    rss = double(sim_data.RSS_rx2(:));
else
    error('[build_rssd_lut] Unsupported antenna index: %d', idx);
end
end

function monotonic_range = detect_monotonic_range(ang_axis, rssd_curve)
if numel(ang_axis) < 2
    monotonic_range = [ang_axis(1), ang_axis(1)];
    return;
end

slope_sign = sign(diff(rssd_curve));
for idx = 2:numel(slope_sign)
    if slope_sign(idx) == 0
        slope_sign(idx) = slope_sign(idx - 1);
    end
end
if ~isempty(slope_sign) && slope_sign(1) == 0
    first_nz = find(slope_sign ~= 0, 1, 'first');
    if ~isempty(first_nz)
        slope_sign(1:first_nz-1) = slope_sign(first_nz);
    else
        slope_sign(:) = 1;
    end
end

break_points = find(diff(slope_sign) ~= 0) + 1;
seg_start = [1; break_points(:)];
seg_end = [break_points(:); numel(ang_axis)];
[~, best_seg] = max(seg_end - seg_start + 1);

monotonic_range = [ang_axis(seg_start(best_seg)), ang_axis(seg_end(best_seg))];
end
