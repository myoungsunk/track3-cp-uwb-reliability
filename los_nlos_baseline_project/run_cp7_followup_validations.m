function outputs = run_cp7_followup_validations(cfg_override)
% RUN_CP7_FOLLOWUP_VALIDATIONS
% Validation 4: Single-RX vs Dual-RX bootstrap delta-AUC
% Validation 5: Mechanism subgroup consistency checks

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cfg = default_config(script_dir, project_root);
if nargin >= 1 && isstruct(cfg_override)
    cfg = merge_config(cfg, cfg_override);
end

ensure_dir(cfg.results_dir);
ensure_reviewer_outputs_exist(cfg);

outputs = struct();
outputs.config = cfg;
outputs.targets = struct();

combined_rx = table();
combined_bootstrap = table();
combined_bootstrap_raw = table();
combined_mechanism = table();

for idx_target = 1:numel(cfg.targets)
    target_name = cfg.targets(idx_target);
    fprintf('\n=== CP7 Follow-up Validations: %s ===\n', target_name);
    dataset_table = load_target_dataset(target_name, cfg);
    meta_table = load_target_metadata(dataset_table, cfg);

    target_outputs = run_target_followups(target_name, dataset_table, meta_table, cfg);
    outputs.targets.(char(target_name)) = target_outputs;

    rx_block = target_outputs.rx_model_summary;
    rx_block.label_target = repmat(string(target_name), height(rx_block), 1);
    rx_block = movevars(rx_block, 'label_target', 'Before', 'scope');
    combined_rx = [combined_rx; rx_block]; %#ok<AGROW>

    boot_block = target_outputs.bootstrap_summary;
    boot_block.label_target = repmat(string(target_name), height(boot_block), 1);
    boot_block = movevars(boot_block, 'label_target', 'Before', 'scope');
    combined_bootstrap = [combined_bootstrap; boot_block]; %#ok<AGROW>

    boot_raw_block = target_outputs.bootstrap_raw;
    if ~isempty(boot_raw_block)
        boot_raw_block.label_target = repmat(string(target_name), height(boot_raw_block), 1);
        boot_raw_block = movevars(boot_raw_block, 'label_target', 'Before', 'scope');
        combined_bootstrap_raw = [combined_bootstrap_raw; boot_raw_block]; %#ok<AGROW>
    end

    mech_block = target_outputs.mechanism_table;
    mech_block.label_target = repmat(string(target_name), height(mech_block), 1);
    mech_block = movevars(mech_block, 'label_target', 'Before', 'subset_name');
    combined_mechanism = [combined_mechanism; mech_block]; %#ok<AGROW>
end

writetable(combined_rx, fullfile(cfg.results_dir, 'rx_model_summary_all_targets.csv'));
writetable(combined_bootstrap, fullfile(cfg.results_dir, 'dual_rx_bootstrap_summary_all_targets.csv'));
if ~isempty(combined_bootstrap_raw)
    writetable(combined_bootstrap_raw, fullfile(cfg.results_dir, 'dual_rx_bootstrap_raw_all_targets.csv'));
end
writetable(combined_mechanism, fullfile(cfg.results_dir, 'mechanism_subgroup_summary_all_targets.csv'));

write_summary_markdown(outputs, combined_rx, combined_bootstrap, combined_mechanism, cfg);

outputs.rx_model_summary = combined_rx;
outputs.bootstrap_summary = combined_bootstrap;
outputs.bootstrap_raw = combined_bootstrap_raw;
outputs.mechanism_summary = combined_mechanism;
outputs.timestamp = datetime('now');
save(fullfile(cfg.results_dir, 'cp7_followup_validations_outputs.mat'), 'outputs', '-v7.3');
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;
cfg.reviewer_results_dir = fullfile(script_dir, 'results', 'cp7_reviewer_diagnostics');
cfg.results_dir = fullfile(script_dir, 'results', 'cp7_followup_validations');
cfg.targets = ["material", "geometric"];
cfg.scopes = ["B", "C", "B+C"];
cfg.random_seed = 42;
cfg.cv_folds = 5;
cfg.classification_threshold = 0.5;
cfg.logistic_lambda = 1e-2;
cfg.bootstrap_repeats = 1000;
cfg.mechanism_bootstrap_repeats = 1000;
cfg.minority_warn_threshold = 3;
cfg.cv_strategy = "stratified_kfold";
cfg.bootstrap_mode = "refit";

cfg.baseline_features = { ...
    'fp_energy_db', ...
    'skewness_pdp', ...
    'kurtosis_pdp', ...
    'mean_excess_delay_ns', ...
    'rms_delay_spread_ns'};
cfg.rx1_features = {'gamma_CP_rx1', 'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1'};
cfg.rx2_features = {'gamma_CP_rx2', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'};
cfg.dual_features = [cfg.rx1_features, cfg.rx2_features];
cfg.all_features = [cfg.baseline_features, cfg.dual_features];

cfg.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
end

function ensure_dir(dirpath)
if ~exist(dirpath, 'dir')
    mkdir(dirpath);
end
end

function ensure_reviewer_outputs_exist(cfg)
required_csv = fullfile(cfg.reviewer_results_dir, 'material', 'cp7_target_dataset.csv');
if isfile(required_csv)
    return;
end

current_dir = pwd;
cleanup_obj = onCleanup(@() cd(current_dir));
cd(cfg.script_dir);
run_cp7_reviewer_diagnostics();
clear cleanup_obj;
cd(current_dir);
end

function dataset_table = load_target_dataset(target_name, cfg)
path_csv = fullfile(cfg.reviewer_results_dir, char(target_name), 'cp7_target_dataset.csv');
if ~isfile(path_csv)
    error('[run_cp7_followup_validations] Missing reviewer dataset: %s', path_csv);
end

dataset_table = readtable(path_csv, 'TextType', 'string');
dataset_table.case_name = string(dataset_table.case_name);
dataset_table.scenario = string(dataset_table.scenario);
dataset_table.polarization = string(dataset_table.polarization);
dataset_table.label = logical(dataset_table.label);
dataset_table.valid_for_cp7_model = logical(dataset_table.valid_for_cp7_model);
end

function meta_table = load_target_metadata(dataset_table, cfg)
label_meta = readtable(cfg.label_csv, 'TextType', 'string');
label_meta.scenario = string(label_meta.scenario);
label_meta.hit_objects = string(label_meta.hit_objects);
label_meta.hit_materials = string(label_meta.hit_materials);
label_meta.criterion = string(label_meta.criterion);
label_meta.key = compose_position_key(label_meta.scenario, label_meta.x_m, label_meta.y_m);

meta_table = outerjoin( ...
    dataset_table(:, {'key', 'case_name', 'scenario', 'x_m', 'y_m', 'label'}), ...
    label_meta(:, {'key', 'tag_id', 'geometric_class', 'material_class', 'penetration_loss_db', 'num_hits', 'hit_objects', 'hit_materials', 'criterion'}), ...
    'Keys', 'key', 'MergeKeys', true, 'Type', 'left');
end

function target_outputs = run_target_followups(target_name, dataset_table, meta_table, cfg)
target_dir = fullfile(cfg.results_dir, char(target_name));
ensure_dir(target_dir);

rx_model_summary = table();
bootstrap_summary = table();
bootstrap_raw = table();
rx_cv_records = struct([]);

for idx_scope = 1:numel(cfg.scopes)
    scope_name = cfg.scopes(idx_scope);
    [scope_models, scope_bootstrap, scope_bootstrap_raw, scope_cv_record] = run_rx_scope_validation(scope_name, dataset_table, cfg);
    rx_model_summary = [rx_model_summary; scope_models]; %#ok<AGROW>
    bootstrap_summary = [bootstrap_summary; scope_bootstrap]; %#ok<AGROW>
    bootstrap_raw = [bootstrap_raw; scope_bootstrap_raw]; %#ok<AGROW>
    if ~isempty(scope_cv_record)
        rx_cv_records = [rx_cv_records; scope_cv_record(:)]; %#ok<AGROW>
    end
end

mechanism_table = run_mechanism_validation(target_name, dataset_table, meta_table, cfg);

writetable(rx_model_summary, fullfile(target_dir, 'rx_model_summary.csv'));
writetable(bootstrap_summary, fullfile(target_dir, 'dual_rx_bootstrap_summary.csv'));
if ~isempty(bootstrap_raw)
    writetable(bootstrap_raw, fullfile(target_dir, 'dual_rx_bootstrap_raw.csv'));
end
writetable(mechanism_table, fullfile(target_dir, 'mechanism_subgroup_summary.csv'));
if ~isempty(rx_cv_records)
    save(fullfile(target_dir, 'rx_cv_records.mat'), 'rx_cv_records');
end

target_outputs = struct();
target_outputs.rx_model_summary = rx_model_summary;
target_outputs.bootstrap_summary = bootstrap_summary;
target_outputs.bootstrap_raw = bootstrap_raw;
target_outputs.mechanism_table = mechanism_table;
target_outputs.rx_cv_records = rx_cv_records;
end

function [rx_model_rows, bootstrap_row, bootstrap_raw, cv_record] = run_rx_scope_validation(scope_name, dataset_table, cfg)
scope_mask = scope_mask_from_name(dataset_table.scenario, scope_name);
scope_table = dataset_table(scope_mask & dataset_table.valid_for_cp7_model, :);
labels = logical(scope_table.label);

rx_model_rows = table();
bootstrap_row = table();
bootstrap_raw = table();
cv_record = struct([]);

folds = safe_cv_folds(labels, cfg.cv_folds);
if isempty(scope_table) || numel(unique(labels)) < 2 || folds < 2
    model_names = ["baseline_plus_rx1", "baseline_plus_rx2", "baseline_plus_dual"];
    for idx = 1:numel(model_names)
        row = table();
        row.scope = string(scope_name);
        row.model_name = model_names(idx);
        row.n_samples = height(scope_table);
        row.n_los = sum(labels);
        row.n_nlos = sum(~labels);
        row.status = "insufficient_scope";
        row.auc = NaN;
        row.brier_score = NaN;
        row.accuracy = NaN;
        rx_model_rows = [rx_model_rows; row]; %#ok<AGROW>
    end

    bootstrap_row = table();
    bootstrap_row.scope = string(scope_name);
    bootstrap_row.n_samples = height(scope_table);
    bootstrap_row.n_boot_valid = 0;
    bootstrap_row.auc_rx1 = NaN;
    bootstrap_row.auc_rx2 = NaN;
    bootstrap_row.auc_dual = NaN;
    bootstrap_row.auc_best_single = NaN;
    bootstrap_row.delta_auc_dual_minus_best_single = NaN;
    bootstrap_row.ci_low = NaN;
    bootstrap_row.ci_high = NaN;
    bootstrap_row.p_dual_le_best = NaN;
    bootstrap_row.status = "insufficient_scope";
    return;
end

features_rx1 = [cfg.baseline_features, cfg.rx1_features];
features_rx2 = [cfg.baseline_features, cfg.rx2_features];
features_dual = [cfg.baseline_features, cfg.dual_features];
cv_plan = build_cv_plan(scope_table, labels, folds, cfg.random_seed, cfg.cv_strategy);

[score_rx1, pred_rx1] = cross_validated_logistic(scope_table, labels, features_rx1, cv_plan, cfg);
[score_rx2, pred_rx2] = cross_validated_logistic(scope_table, labels, features_rx2, cv_plan, cfg);
[score_dual, pred_dual] = cross_validated_logistic(scope_table, labels, features_dual, cv_plan, cfg);

rx_model_rows = [ ...
    build_rx_model_row(scope_name, "baseline_plus_rx1", labels, score_rx1, pred_rx1); ...
    build_rx_model_row(scope_name, "baseline_plus_rx2", labels, score_rx2, pred_rx2); ...
    build_rx_model_row(scope_name, "baseline_plus_dual", labels, score_dual, pred_dual)];

cv_record = struct();
cv_record.scope = string(scope_name);
cv_record.seed = cfg.random_seed;
cv_record.strategy = string(cv_plan.strategy);
cv_record.fold_assignment = cv_plan.fold_assignment;
cv_record.num_folds = cv_plan.num_test_sets;

[bootstrap_row, bootstrap_raw] = bootstrap_dual_gain( ...
    scope_name, scope_table, labels, score_rx1, score_rx2, score_dual, ...
    features_rx1, features_rx2, features_dual, cfg);
end

function row = build_rx_model_row(scope_name, model_name, labels, scores, predictions)
metric_row = metrics_table_from_vectors(labels, scores, predictions, model_name);
row = table();
row.scope = string(scope_name);
row.model_name = string(model_name);
row.n_samples = metric_row.n_samples;
row.n_los = metric_row.n_los;
row.n_nlos = metric_row.n_nlos;
row.status = "ok";
row.auc = metric_row.auc;
row.brier_score = metric_row.brier_score;
row.accuracy = metric_row.accuracy;
end

function [row, raw_table] = bootstrap_dual_gain(scope_name, scope_table, labels, score_rx1, score_rx2, score_dual, features_rx1, features_rx2, features_dual, cfg)
n_samples = numel(labels);
delta_values = nan(cfg.bootstrap_repeats, 1);
raw_table = table();

auc_rx1 = compute_auc(labels, score_rx1);
auc_rx2 = compute_auc(labels, score_rx2);
auc_dual = compute_auc(labels, score_dual);
auc_best_single = max([auc_rx1, auc_rx2]);

for idx_boot = 1:cfg.bootstrap_repeats
    rng(cfg.random_seed + idx_boot - 1);
    sample_idx = randi(n_samples, n_samples, 1);
    scope_boot = scope_table(sample_idx, :);
    labels_b = labels(sample_idx);
    if numel(unique(labels_b)) < 2
        continue;
    end

    folds_b = safe_cv_folds(labels_b, cfg.cv_folds);
    if folds_b < 2
        continue;
    end

    cv_plan_b = build_cv_plan(scope_boot, labels_b, folds_b, cfg.random_seed + idx_boot - 1, cfg.cv_strategy);
    switch string(get_param(cfg, 'bootstrap_mode', "refit"))
        case "refit"
            [score_rx1_b, ~] = cross_validated_logistic(scope_boot, labels_b, features_rx1, cv_plan_b, cfg);
            [score_rx2_b, ~] = cross_validated_logistic(scope_boot, labels_b, features_rx2, cv_plan_b, cfg);
            [score_dual_b, ~] = cross_validated_logistic(scope_boot, labels_b, features_dual, cv_plan_b, cfg);
        otherwise
            score_rx1_b = score_rx1(sample_idx);
            score_rx2_b = score_rx2(sample_idx);
            score_dual_b = score_dual(sample_idx);
    end

    auc_rx1_b = compute_auc(labels_b, score_rx1_b);
    auc_rx2_b = compute_auc(labels_b, score_rx2_b);
    auc_dual_b = compute_auc(labels_b, score_dual_b);
    delta_values(idx_boot) = auc_dual_b - max([auc_rx1_b, auc_rx2_b]);

    boot_row = table();
    boot_row.scope = string(scope_name);
    boot_row.boot_idx = idx_boot;
    boot_row.seed = cfg.random_seed + idx_boot - 1;
    boot_row.auc_rx1 = auc_rx1_b;
    boot_row.auc_rx2 = auc_rx2_b;
    boot_row.auc_dual = auc_dual_b;
    boot_row.delta_auc_dual_minus_best_single = delta_values(idx_boot);
    raw_table = [raw_table; boot_row]; %#ok<AGROW>
end

valid_delta = delta_values(isfinite(delta_values));
row = table();
row.scope = string(scope_name);
row.n_samples = n_samples;
row.n_boot_valid = numel(valid_delta);
row.auc_rx1 = auc_rx1;
row.auc_rx2 = auc_rx2;
row.auc_dual = auc_dual;
row.auc_best_single = auc_best_single;
row.delta_auc_dual_minus_best_single = auc_dual - auc_best_single;

if isempty(valid_delta)
    row.ci_low = NaN;
    row.ci_high = NaN;
    row.p_dual_le_best = NaN;
    row.status = "bootstrap_failed";
else
    row.ci_low = quantile(valid_delta, 0.025);
    row.ci_high = quantile(valid_delta, 0.975);
    row.p_dual_le_best = mean(valid_delta <= 0);
    row.status = "ok";
end
end

function mechanism_table = run_mechanism_validation(target_name, dataset_table, meta_table, cfg)
joined = outerjoin(dataset_table, meta_table(:, {'key', 'tag_id', 'geometric_class', 'material_class', 'penetration_loss_db', 'num_hits', 'hit_objects', 'hit_materials', 'criterion'}), ...
    'Keys', 'key', 'MergeKeys', true, 'Type', 'left');
joined = joined(joined.valid_for_cp7_model, :);

mechanism_table = table();
if string(target_name) == "geometric"
    subset_defs = { ...
        struct('name', "geom_B_metal_single_bounce", 'mask', make_geom_subset(joined, "B", "metal"), 'focus', {{'a_FP_LHCP_rx1','a_FP_LHCP_rx2'}}), ...
        struct('name', "geom_B_glass_partition", 'mask', make_geom_subset(joined, "B", "glass"), 'focus', {{'a_FP_LHCP_rx1','a_FP_LHCP_rx2'}}), ...
        struct('name', "geom_C_dense_clutter_all", 'mask', joined.scenario == "C", 'focus', {{'a_FP_LHCP_rx1','a_FP_LHCP_rx2'}})};
    target_features = {'a_FP_LHCP_rx1','a_FP_LHCP_rx2','gamma_CP_rx1','gamma_CP_rx2'};
else
    subset_defs = { ...
        struct('name', "mat_BC_hardblock_metal", 'mask', make_material_subset(joined, "metal"), 'focus', {{'a_FP_RHCP_rx1','a_FP_RHCP_rx2'}}), ...
        struct('name', "mat_C_softblock_wood", 'mask', make_material_subset(joined, "wood"), 'focus', {{'a_FP_RHCP_rx1','a_FP_RHCP_rx2'}}), ...
        struct('name', "mat_C_all", 'mask', joined.scenario == "C", 'focus', {{'a_FP_RHCP_rx1','a_FP_RHCP_rx2'}})};
    target_features = {'a_FP_RHCP_rx1','a_FP_RHCP_rx2','gamma_CP_rx1','gamma_CP_rx2'};
end

for idx_subset = 1:numel(subset_defs)
    def = subset_defs{idx_subset};
    subset_table = joined(def.mask, :);
    labels = logical(subset_table.label);

    for idx_feature = 1:numel(target_features)
        feature_name = target_features{idx_feature};
        row = table();
        row.subset_name = string(def.name);
        row.feature_name = string(feature_name);
        row.n_samples = height(subset_table);
        row.n_los = sum(labels);
        row.n_nlos = sum(~labels);
        row.focus_feature = any(strcmp(def.focus, feature_name));
        row.n_boot_valid = NaN;
        row.auc_ci_low = NaN;
        row.auc_ci_high = NaN;
        row.p_auc_le_0p5 = NaN;

        if row.n_los == 0 || row.n_nlos == 0
            row.auc = NaN;
            row.status = "single_class";
        else
            row.auc = compute_auc(labels, subset_table.(feature_name));
            [row.n_boot_valid, row.auc_ci_low, row.auc_ci_high, row.p_auc_le_0p5] = bootstrap_auc_ci( ...
                labels, subset_table.(feature_name), cfg.mechanism_bootstrap_repeats, cfg.random_seed + idx_subset + idx_feature);
            if min([row.n_los, row.n_nlos]) < cfg.minority_warn_threshold
                row.status = "underpowered";
            else
                row.status = "ok";
            end
        end

        mechanism_table = [mechanism_table; row]; %#ok<AGROW>
    end
end
end

function mask = make_geom_subset(joined, scenario_name, nlos_material)
mask = joined.scenario == string(scenario_name) & ...
    (joined.label == 1 | (joined.label == 0 & lower(joined.hit_materials) == lower(string(nlos_material))));
end

function mask = make_material_subset(joined, nlos_material)
mask = joined.label == 1 | (joined.label == 0 & lower(joined.hit_materials) == lower(string(nlos_material)));
end

function [score, pred] = cross_validated_logistic(dataset_table, labels, feature_names, cv_plan, cfg)
X_all = dataset_table{:, feature_names};
n_samples = size(X_all, 1);
score = nan(n_samples, 1);
pred = false(n_samples, 1);

for idx_fold = 1:cv_plan.num_test_sets
    train_mask = cv_plan.train_masks{idx_fold};
    test_mask = cv_plan.test_masks{idx_fold};

    X_train = X_all(train_mask, :);
    y_train = labels(train_mask);
    X_test = X_all(test_mask, :);

    [X_train_norm, norm_params] = normalize_feature_matrix(X_train);
    X_test_norm = apply_normalization(X_test, norm_params);
    model = fit_logistic_model(X_train_norm, y_train, cfg);

    score(test_mask) = predict_with_model(model, X_test_norm);
    pred(test_mask) = score(test_mask) >= cfg.classification_threshold;
end
end

function cv_plan = build_cv_plan(dataset_table, labels, folds, seed, strategy)
strategy = string(strategy);
labels = logical(labels(:));
n_samples = numel(labels);

switch strategy
    case "stratified_kfold"
        rng(seed);
        cv = cvpartition(labels, 'KFold', folds);
        train_masks = cell(cv.NumTestSets, 1);
        test_masks = cell(cv.NumTestSets, 1);
        fold_assignment = zeros(n_samples, 1);
        for idx_fold = 1:cv.NumTestSets
            train_masks{idx_fold} = training(cv, idx_fold);
            test_masks{idx_fold} = test(cv, idx_fold);
            fold_assignment(test_masks{idx_fold}) = idx_fold;
        end
        cv_plan = struct();
        cv_plan.strategy = strategy;
        cv_plan.seed = seed;
        cv_plan.num_test_sets = cv.NumTestSets;
        cv_plan.train_masks = train_masks;
        cv_plan.test_masks = test_masks;
        cv_plan.fold_assignment = fold_assignment;
    case "leave_one_position_out"
        if ismember('key', dataset_table.Properties.VariableNames)
            group_key = string(dataset_table.key);
        else
            group_key = compose_position_key(dataset_table.scenario, dataset_table.x_m, dataset_table.y_m);
        end
        [~, ~, group_idx] = unique(group_key, 'stable');
        n_group = max(group_idx);
        train_masks = cell(n_group, 1);
        test_masks = cell(n_group, 1);
        fold_assignment = zeros(n_samples, 1);
        for idx_fold = 1:n_group
            test_masks{idx_fold} = group_idx == idx_fold;
            train_masks{idx_fold} = ~test_masks{idx_fold};
            fold_assignment(test_masks{idx_fold}) = idx_fold;
        end
        cv_plan = struct();
        cv_plan.strategy = strategy;
        cv_plan.seed = seed;
        cv_plan.num_test_sets = n_group;
        cv_plan.train_masks = train_masks;
        cv_plan.test_masks = test_masks;
        cv_plan.fold_assignment = fold_assignment;
    otherwise
        error('[run_cp7_followup_validations] Unsupported cv strategy: %s', strategy);
end
end

function [X_norm, params] = normalize_feature_matrix(X)
mean_values = mean(X, 1, 'omitnan');
std_values = std(X, 0, 1, 'omitnan');
std_values(~isfinite(std_values) | std_values == 0) = 1;
X_norm = (X - mean_values) ./ std_values;

params = struct();
params.mean_values = mean_values;
params.std_values = std_values;
end

function X_norm = apply_normalization(X, params)
X_norm = (X - params.mean_values) ./ params.std_values;
end

function model = fit_logistic_model(X, y, cfg)
weights = compute_class_weights(y);
model = struct();

try
    mdl = fitclinear(X, y, ...
        'Learner', 'logistic', ...
        'Regularization', 'ridge', ...
        'Lambda', cfg.logistic_lambda, ...
        'Solver', 'lbfgs', ...
        'Weights', weights);
    model.backend = "fitclinear";
    model.mdl_object = mdl;
catch exception_info
    warning('[run_cp7_followup_validations] fitclinear failed (%s). Falling back to fitglm.', ...
        exception_info.message);
    predictor_names = make_predictor_names(size(X, 2));
    train_table = array2table(X, 'VariableNames', predictor_names);
    train_table.label = y;
    mdl = fitglm(train_table, 'label ~ .', 'Distribution', 'binomial', 'Weights', weights);
    model.backend = "fitglm";
    model.mdl_object = mdl;
    model.predictor_names = predictor_names;
end
end

function weights = compute_class_weights(y)
y = logical(y(:));
n_total = numel(y);
n_pos = sum(y);
n_neg = sum(~y);
weights = ones(n_total, 1);
if n_pos == 0 || n_neg == 0
    return;
end
weights(y) = 0.5 * n_total / n_pos;
weights(~y) = 0.5 * n_total / n_neg;
end

function predictor_names = make_predictor_names(n_feature)
predictor_names = arrayfun(@(idx) sprintf('x%d', idx), 1:n_feature, 'UniformOutput', false);
end

function score = predict_with_model(model, X_norm)
switch string(model.backend)
    case "fitclinear"
        linear_score = X_norm * double(model.mdl_object.Beta(:)) + double(model.mdl_object.Bias);
        score = logistic_sigmoid(linear_score);
    case "fitglm"
        predict_table = array2table(X_norm, 'VariableNames', model.predictor_names);
        score = predict(model.mdl_object, predict_table);
    otherwise
        error('[run_cp7_followup_validations] Unsupported backend: %s', string(model.backend));
end
end

function y = logistic_sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
end

function row = metrics_table_from_vectors(labels, scores, predictions, group_name)
labels = logical(labels(:));
scores = double(scores(:));
predictions = logical(predictions(:));

n_samples = numel(labels);
tp = sum(predictions & labels);
tn = sum(~predictions & ~labels);
fp = sum(predictions & ~labels);
fn = sum(~predictions & labels);

row = table();
row.group_name = string(group_name);
row.n_samples = n_samples;
row.n_los = sum(labels);
row.n_nlos = sum(~labels);
row.accuracy = safe_divide(tp + tn, n_samples);
row.auc = compute_auc(labels, scores);
row.brier_score = mean((scores - double(labels)).^2, 'omitnan');
row.tp = tp;
row.tn = tn;
row.fp = fp;
row.fn = fn;
end

function auc = compute_auc(labels, scores)
labels = logical(labels(:));
scores = double(scores(:));
valid_mask = isfinite(scores);
labels = labels(valid_mask);
scores = scores(valid_mask);
if numel(unique(labels)) < 2
    auc = NaN;
    return;
end
[~, ~, ~, auc] = perfcurve(labels, scores, true);
end

function value = safe_divide(num, den)
if den == 0
    value = NaN;
else
    value = num / den;
end
end

function [n_boot_valid, ci_low, ci_high, p_auc_le_0p5] = bootstrap_auc_ci(labels, scores, n_bootstrap, seed_base)
labels = logical(labels(:));
scores = double(scores(:));
auc_values = nan(n_bootstrap, 1);
n_samples = numel(labels);
for idx_boot = 1:n_bootstrap
    rng(seed_base + idx_boot - 1);
    sample_idx = randi(n_samples, n_samples, 1);
    labels_b = labels(sample_idx);
    if numel(unique(labels_b)) < 2
        continue;
    end
    auc_values(idx_boot) = compute_auc(labels_b, scores(sample_idx));
end
valid_auc = auc_values(isfinite(auc_values));
n_boot_valid = numel(valid_auc);
ci_low = safe_quantile(valid_auc, 0.025);
ci_high = safe_quantile(valid_auc, 0.975);
if isempty(valid_auc)
    p_auc_le_0p5 = NaN;
else
    p_auc_le_0p5 = mean(valid_auc <= 0.5);
end
end

function value = safe_quantile(x, q)
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = quantile(x, q);
end
end

function mask = scope_mask_from_name(scenario, scope_name)
scenario = string(scenario);
switch string(scope_name)
    case "B"
        mask = scenario == "B";
    case "C"
        mask = scenario == "C";
    case "B+C"
        mask = scenario == "B" | scenario == "C";
    otherwise
        error('[run_cp7_followup_validations] Unsupported scope: %s', string(scope_name));
end
end

function folds = safe_cv_folds(labels, requested_folds)
labels = logical(labels(:));
if isempty(labels) || numel(unique(labels)) < 2
    folds = 0;
    return;
end
minority = min(sum(labels), sum(~labels));
folds = min([requested_folds, minority, numel(labels)]);
if folds < 2
    folds = 0;
end
end

function cfg = merge_config(cfg, overrides)
if nargin < 2 || ~isstruct(overrides)
    return;
end
fields = fieldnames(overrides);
for idx = 1:numel(fields)
    cfg.(fields{idx}) = overrides.(fields{idx});
end
end

function value = get_param(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    value = s.(field_name);
else
    value = default_value;
end
end

function key = compose_position_key(scenario, x_m, y_m)
scenario = string(scenario);
x_m = double(x_m);
y_m = double(y_m);
key = strings(numel(x_m), 1);
for idx = 1:numel(x_m)
    key(idx) = sprintf('%s|%.3f|%.3f', upper(char(scenario(idx))), x_m(idx), y_m(idx));
end
end

function write_summary_markdown(outputs, combined_rx, combined_bootstrap, combined_mechanism, cfg)
path_md = fullfile(cfg.results_dir, 'cp7_followup_validation_report.md');
fid = fopen(path_md, 'w');
if fid < 0
    error('Failed to open markdown summary: %s', path_md);
end
cleanup_obj = onCleanup(@() fclose(fid));

fprintf(fid, '# CP7 Follow-up Validation Report\n\n');
fprintf(fid, '## Validation 4: Single-RX vs Dual-RX\n\n');
fprintf(fid, '| Target | Scope | Model | AUC | Brier | Accuracy |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|\n');
for idx = 1:height(combined_rx)
    row = combined_rx(idx, :);
    fprintf(fid, '| %s | %s | %s | %.4f | %.4f | %.4f |\n', ...
        char(row.label_target), char(row.scope), char(row.model_name), row.auc, row.brier_score, row.accuracy);
end

fprintf(fid, '\n### Dual-RX Gain vs Best Single-RX\n\n');
fprintf(fid, '| Target | Scope | Delta AUC | 95%% CI | p(dual <= best) |\n');
fprintf(fid, '|---|---|---:|---|---:|\n');
for idx = 1:height(combined_bootstrap)
    row = combined_bootstrap(idx, :);
    fprintf(fid, '| %s | %s | %.4f | [%.4f, %.4f] | %.4f |\n', ...
        char(row.label_target), char(row.scope), row.delta_auc_dual_minus_best_single, ...
        row.ci_low, row.ci_high, row.p_dual_le_best);
end

fprintf(fid, '\n## Validation 5: Mechanism Subgroups\n\n');
fprintf(fid, '| Target | Subset | Feature | n(L/N) | AUC | 95%% CI | Status |\n');
fprintf(fid, '|---|---|---|---|---:|---|---|\n');
for idx = 1:height(combined_mechanism)
    row = combined_mechanism(idx, :);
    fprintf(fid, '| %s | %s | %s | %d/%d | %.4f | [%.4f, %.4f] | %s |\n', ...
        char(row.label_target), char(row.subset_name), char(row.feature_name), ...
        row.n_los, row.n_nlos, row.auc, row.auc_ci_low, row.auc_ci_high, char(row.status));
end
end
