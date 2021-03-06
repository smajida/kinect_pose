% You should put all your code for recognizing unknown actions in this file.
% Describe the method you used in YourMethod.txt.
% Don't forget to call SavePrediction() at the end with your predicted labels to save them for submission, then submit using submit.m
% File: RecognizeActions.m
%
% Copyright (C) Daphne Koller, Stanford Univerity, 2012

function [accuracy, predicted_labels] = RecognizeUnknownActions(datasetTrain, datasetTest, G, maxIter)

% INPUTS
% datasetTrain: dataset for training models, see PA for details
% datasetTest: dataset for testing models, see PA for details
% G: graph parameterization as explained in PA decription
% maxIter: max number of iterations to run for EM

% OUTPUTS
% accuracy: recognition accuracy, defined as (#correctly classified examples / #total examples)
% predicted_labels: N x 1 vector with the predicted labels for each of the instances in datasetTest, with N being the number of unknown test instances


% Train a model for each action
% Note that all actions share the same graph parameterization and number of max iterations
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% YOUR CODE HERE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

TA = length(datasetTrain); % num of types of actions
models = repmat(struct('P',[],'loglikelihood',[],'ClassProb',[],'PairProb',[]),TA,1);

for step = 1:TA
    [P loglikelihood ClassProb PairProb] = EM_HMM(datasetTrain(step).actionData, ...
        datasetTrain(step).poseData, G, datasetTrain(step).InitialClassProb, ...
        datasetTrain(step).InitialPairProb, maxIter);
    models(step).P = P;
    models(step).loglikelihood = loglikelihood;
    models(step).ClassProb = ClassProb;
    models(step).PairProb = PairProb;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Classify each of the instances in datasetTrain
% Compute and return the predicted labels and accuracy
% Accuracy is defined as (#correctly classified examples / #total examples)
% Note that all actions share the same graph parameterization

accuracy = 0;
predicted_labels = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% YOUR CODE HERE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

NA = length(datasetTest.actionData);
NP = length(datasetTest.poseData);
likelihoods = zeros(NA,TA);
K = TA;


for step_ta = 1:TA
    % calculate the singleton probabilities
    P = models(step_ta).P;
    loglikelihood = models(step_ta).loglikelihood;
    ClassProb = models(step_ta).ClassProb;
    PairProb = models(step_ta).PairProb;
    
    
    logEmissionProb = zeros(NP,TA);

    dataset = datasetTest.poseData;
    for step1 = 1:NP
        temp_prob1 = 0;
        graph = G;
        for k = 1:K % all

            temp_prob2 = 0;

            for step2 = 1:10
                if graph(step2, 1) == 0 % no parent
                    temp_prob2 = temp_prob2 + ...
                        lognormpdf(dataset(step1,step2,1),P.clg(step2).mu_y(k),P.clg(step2).sigma_y(k)) + ...
                        lognormpdf(dataset(step1,step2,2),P.clg(step2).mu_x(k),P.clg(step2).sigma_x(k)) + ...
                        lognormpdf(dataset(step1,step2,3),P.clg(step2).mu_angle(k),P.clg(step2).sigma_angle(k)) ;
                else
                    pa = [1, dataset(step1,graph(step2,2),1), dataset(step1,graph(step2,2),2), dataset(step1,graph(step2,2),3)];
                    temp_prob2 = temp_prob2 + ...
                        lognormpdf(dataset(step1,step2,1), pa*P.clg(step2).theta(k,1:4)', P.clg(step2).sigma_y(k)) + ...
                        lognormpdf(dataset(step1,step2,2), pa*P.clg(step2).theta(k,5:8)', P.clg(step2).sigma_x(k)) + ...
                        lognormpdf(dataset(step1,step2,3), pa*P.clg(step2).theta(k,9:12)', P.clg(step2).sigma_angle(k)) ;
                end
            end

            logEmissionProb(step1,k) = temp_prob2;
        end
    end
    
    % unroll the matrix to a vactor to fit for the val field
    pair_factor_val = zeros(1, K*K);
    asgn = IndexToAssignment( 1:K*K, [K,K]);
    for step = 1:K*K
      pair_factor_val(1,step) = log(P.transMatrix( asgn(step,1), asgn(step,2) ));
    end

    % build the factors
    for step = 1:NA
      num_pose = length(datasetTest.actionData(step).marg_ind);
      num_pair = length(datasetTest.actionData(step).pair_ind);
      single_factors = repmat(struct('var',[],'card',[],'val',[]), 1,num_pose+1);
      pair_factors = repmat(struct('var',[],'card',[],'val',[]), 1,num_pair);

      single_factors(1).var = [1];
      single_factors(1).card = [K];
      single_factors(1).val = log(P.c);
      for step2 = 1:num_pose
          single_factors(step2+1).var = [step2];
          single_factors(step2+1).card = [K];
          single_factors(step2+1).val = logEmissionProb(datasetTest.actionData(step).marg_ind(step2),:);
      end
      for step2 = 1:num_pair
          pair_factors(step2).var = [step2, step2+1];
          pair_factors(step2).card = [K,K];
          pair_factors(step2).val = pair_factor_val;
      end

      [M, PCalibrated] = ComputeExactMarginalsHMM([single_factors, pair_factors]);

      for step2 = 1:num_pose
          ClassProb( datasetTest.actionData(step).marg_ind(step2),: ) = exp( M(step2).val );
      end
      for step2 = 1:num_pair
          %tmp = FactorSum(M(step2),M(step2+1));
          %PairProb( actionData(step).pair_ind(step2),: ) = exp(tmp.val);
          PairProb(datasetTest.actionData(step).pair_ind(step2),:) = exp(PCalibrated.cliqueList(step2).val - logsumexp(PCalibrated.cliqueList(step2).val) );
      end
      likelihoods(step,step_ta) = likelihoods(step,step_ta) + logsumexp(PCalibrated.cliqueList(1).val);
    end
end

predicted_labels = zeros(NA,1);

for step = 1:NA
    [~, pos] = max( likelihoods(step,:) );
    predicted_labels(step) = pos;
end

accuracy = sum((predicted_labels==datasetTest.labels)) / NA;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
