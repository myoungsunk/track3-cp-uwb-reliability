function ablation_results = run_ablation_cp3(features, labels, params)
% RUN_ABLATION_CP3 Compare logistic variants with 3 CP features:
% gamma_CP-only, a_FP-only, fp_idx_diff-only, and combined.
if nargin < 3
    params = struct();
end

features = double(features);
labels = logical(labels(:));

if size(features, 1) ~= numel(labels)
    error('[run_ablation_cp3] features rows and labels length must match.');
end
if size(features, 2) < 3
    error('[run_ablation_cp3] features must have at least 3 columns [gamma_CP, a_FP, fp_idx_diff].');
end

valid_mask = all(isfinite(features(:, 1:3)), 2);
features = features(valid_mask, 1:3);
labels = labels(valid_mask);

if numel(unique(labels)) < 2
    error('[run_ablation_cp3] labels must contain both classes.');
end

random_seed = get_param(params, 'random_seed', 42);
cv_folds = get_param(params, 'cv_folds', 5);
rng(random_seed);
cv = cvpartition(labels, 'KFold', cv_folds);

cfg_names = {'gamma_CP_only', 'a_FP_only', 'fp_idx_diff_only', 'combined'};
row_auc = zeros(4, 1);
row_acc = zeros(4, 1);
row_f1 = zeros(4, 1);
row_ece = zeros(4, 1);

for cfg_idx = 1:4
    params_cfg = params;
    params_cfg.cv_partition = cv;
    params_cfg.log10_rcp = false;

    if cfg_idx == 1
        x_cfg = features(:, 1);
    elseif cfg_idx == 2
        x_cfg = features(:, 2);
    elseif cfg_idx == 3
        x_cfg = features(:, 3);
    else
        x_cfg = features(:, 1:3);
    end

    [model_cfg, norm_cfg] = train_logistic(x_cfg, labels, params_cfg);
    eval_cfg = eval_roc_calibration(model_cfg, norm_cfg, x_cfg, labels, ...
        setfield(params_cfg, 'save_outputs', false)); %#ok<SFLD>

    row_auc(cfg_idx) = model_cfg.cv_auc;
    row_acc(cfg_idx) = model_cfg.cv_accuracy;
    row_f1(cfg_idx) = eval_cfg.f1;
    row_ece(cfg_idx) = eval_cfg.ece;
end

delta_auc = row_auc - row_auc(4);

ablation_results = table( ...
    string(cfg_names(:)), ...
    row_auc, ...
    row_acc, ...
    row_f1, ...
    row_ece, ...
    delta_auc, ...
    'VariableNames', {'config', 'auc', 'accuracy', 'f1', 'ece', 'delta_auc_vs_combined'});

save_outputs = logical(get_param(params, 'save_outputs', true));
if save_outputs
    output_dir = char(get_param(params, 'results_dir', fullfile(pwd, 'results')));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    save(fullfile(output_dir, 'ablation_results_cp3.mat'), 'ablation_results');
    writetable(ablation_results, fullfile(output_dir, 'ablation_results_cp3.csv'));
end
end
