function prob = predict_logistic_prob(model, features_norm)
% PREDICT_LOGISTIC_PROB Predict positive-class probability from train_logistic model backend.
if ~isstruct(model) || ~isfield(model, 'mdl_object')
    error('[predict_logistic_prob] model.mdl_object is required.');
end

features_norm = double(features_norm);
if isfield(model, 'predictor_names')
    n_expected_features = numel(model.predictor_names);
else
    n_expected_features = size(features_norm, 2);
end
if isvector(features_norm)
    if numel(features_norm) == n_expected_features
        features_norm = reshape(features_norm, 1, n_expected_features);
    else
        features_norm = reshape(features_norm, [], 1);
    end
end

n_features = size(features_norm, 2);
if isfield(model, 'predictor_names') && numel(model.predictor_names) == n_features
    predictor_name_list = model.predictor_names;
else
    predictor_name_list = arrayfun(@(k) sprintf('x%d', k), 1:n_features, 'UniformOutput', false);
end

if isfield(model, 'backend')
    backend = lower(string(model.backend));
else
    backend = "fitglm";
end

switch backend
    case "fitglm"
        tbl_in = array2table(features_norm, 'VariableNames', predictor_name_list);
        prob = predict(model.mdl_object, tbl_in);
    case "ridge"
        [~, score_matrix] = predict(model.mdl_object, features_norm);
        prob = positive_class_prob(score_matrix, model.mdl_object.ClassNames);
    otherwise
        error('[predict_logistic_prob] Unsupported model backend: %s', backend);
end

prob = double(prob(:));
prob = min(max(prob, 0), 1);
end

function prob = positive_class_prob(score_matrix, class_names)
if numel(class_names) ~= 2
    error('[predict_logistic_prob] binary class names expected.');
end

if islogical(class_names)
    pos_idx = find(class_names == true, 1, 'first');
else
    pos_idx = find(strcmp(string(class_names), string(true)), 1, 'first');
    if isempty(pos_idx)
        pos_idx = 2;
    end
end

prob = score_matrix(:, pos_idx);
end
