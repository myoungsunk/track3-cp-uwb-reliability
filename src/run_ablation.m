function ablation_results = run_ablation(features, labels, params)
% RUN_ABLATION Compare logistic variants: r_CP-only, a_FP-only, and combined features.
if nargin < 3
    params = struct();
end

features = double(features);
labels = logical(labels(:));

if size(features, 1) ~= numel(labels)
    error('[run_ablation] features rows and labels length must match.');
end
if size(features, 2) < 2
    error('[run_ablation] features must have at least 2 columns [r_CP, a_FP].');
end

valid_mask = all(isfinite(features(:, 1:2)), 2);
features = features(valid_mask, 1:2);
labels = labels(valid_mask);

if numel(unique(labels)) < 2
    error('[run_ablation] labels must contain both classes.');
end

random_seed = get_param(params, 'random_seed', 42);
cv_folds = get_param(params, 'cv_folds', 5);
rng(random_seed);
cv = cvpartition(labels, 'KFold', cv_folds);

cfg_names = {'r_CP_only', 'a_FP_only', 'combined'};
row_auc = zeros(3, 1);
row_acc = zeros(3, 1);
row_f1 = zeros(3, 1);
row_ece = zeros(3, 1);

for cfg_idx = 1:3
    params_cfg = params;
    params_cfg.cv_partition = cv;

    if cfg_idx == 1
        x_cfg = features(:, 1);
        params_cfg.log10_rcp = true;
    elseif cfg_idx == 2
        x_cfg = features(:, 2);
        params_cfg.log10_rcp = false;
    else
        x_cfg = features(:, 1:2);
        params_cfg.log10_rcp = true;
    end

    [model_cfg, norm_cfg] = train_logistic(x_cfg, labels, params_cfg);
    eval_cfg = eval_roc_calibration(model_cfg, norm_cfg, x_cfg, labels, setfield(params_cfg, 'save_outputs', false)); %#ok<SFLD>

    row_auc(cfg_idx) = model_cfg.cv_auc;
    row_acc(cfg_idx) = model_cfg.cv_accuracy;
    row_f1(cfg_idx) = eval_cfg.f1;
    row_ece(cfg_idx) = eval_cfg.ece;
end

delta_auc = row_auc - row_auc(3);

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

    save(fullfile(output_dir, 'ablation_results.mat'), 'ablation_results');
    writetable(ablation_results, fullfile(output_dir, 'ablation_results.csv'));
end
end
