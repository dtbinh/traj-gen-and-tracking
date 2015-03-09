% Robot abstract class is the parent for particular
% robot arm manipulators.

classdef (Abstract) Robot < Model
        
    % Field necessary for all robotic manipulators?
    properties (Abstract)        

        % jacobian
        jac
        % flag for representing learned trajectories
        % in operational (0) or joint space (1) ?
        flag_jspace
        % flag indicating joint space references
        flag_ref_jsp
    end
    
    % methods to be implemented
    methods (Abstract)
        
        % kinematics
        kinematics(q)
        % inverse kinematics
        invKinematics(x)
        % inverse dynamics to get u
        invDynamics(q,qd,qdd)
        % (direct) dynamics to qet Qd = [qd,qdd]
        dynamics(Q,u)
        % make an animation of the robot manipulator
        animateArm(x)
        
    end
    
    % methods that robots share
    methods (Access = public)
        
        %% Generate inputs for a reference
        % using a simple inverse kinematics method
        % if flag is 1 then reference in joint space!
        function Traj = generateInputs(obj,t,ref)

            h = obj.SIM.h;
            dim = obj.SIM.dimx / 2;
            dimu = obj.SIM.dimu;
            Cout = obj.C;
            
            if (obj.flag_ref_jsp)
                q = ref(1:dim,:);
                qd = ref(dim+1:2*dim,:);
            else
                % assuming that only positions are demonstrated
                q = obj.invKinematics(ref);
                qd = diff(q')' / h; 
                % start with zero initial velocity
                %qd = [zeros(dim,1), qd];
                %qdd = [zeros(dim,1), qdd];
                % assume you end with same velocity as before
                qd(:,end+1) = qd(:,end);
            end
            
            qdd = diff(qd')' / h; 
            % assume you end with same acceleration as before
            qdd(:,end+1) = qdd(:,end);
            % this leads to large decelerations!
            % add one more acceleration assuming q(end+1) = q(end)
            %qdd(:,end+1) = (q(:,end-1) - q(:,end))/(h^2);

            % get the desired inputs
            Nu = length(t) - 1;
            uff = zeros(dimu,Nu);
            for i = 1:Nu
                uff(:,i) = obj.invDynamics(q(:,i),qd(:,i),qdd(:,i));
            end
            
            % check for joint space representation
            if obj.flag_jspace == 1
                Traj = Trajectory(t,Cout*[q;qd],uff,[]);
            else
                %xd = obj.jac * qd;
                x =  ref;
                xd = diff(x')'/h;
                xd(:,end+1) = xd(:,end);
                Traj = Trajectory(t,Cout*[x;xd],uff,[]);
            end            
        end
        
        %% Method useful when modifying DMPs directly
        function [Traj,dmps] = generateInputsWithDMP(obj,t,ref)

            h = obj.SIM.h;
            dim = obj.SIM.dimx / 2;
            dimu = obj.SIM.dimu;
            Cout = obj.C;
            
            assert(size(Cout,2)==obj.SIM.dimx,...
                'Currently works only for full observation');
            
            if (obj.flag_ref_jsp)
                qdes = ref(1:dim,:);
                qddes = ref(dim+1:2*dim,:);
            else
                % assuming that only positions are demonstrated
                qdes = obj.invKinematics(ref);
                qddes = diff(qdes')' / h; 
                % assume you end with same velocity as before
                qddes(:,end+1) = qddes(:,end);
            end
            
            % make DMPs that smoothens reference, one for each output
            goal = [qdes(:,end);qddes(:,end)];
            yin = [qdes(:,1);qddes(:,1)];
            numbf = 20;      
            [dmps,s] = obj.dmpTrajectory(t,numbf,goal,yin,[qdes;qddes]);
            
            q = s(1:dim,:);
            qd = s(dim+1:end,:);            
            qdd = diff(qd')' / h; 
            % assume you end with same acceleration as before
            qdd(:,end+1) = qdd(:,end);

            % get the desired inputs
            Nu = length(t) - 1;
            uff = zeros(dimu,Nu);
            for i = 1:Nu
                uff(:,i) = obj.invDynamics(q(:,i),qd(:,i),qdd(:,i));
            end
            
            % check for joint space representation
            if obj.flag_jspace == 1
                Traj = Trajectory(t,Cout*[q;qd],uff,[]);
            else
                %xd = obj.jac * qd;
                x =  ref;
                xd = diff(x')'/h;
                xd(:,end+1) = xd(:,end);
                Traj = Trajectory(t,Cout*[x;xd],uff,[]);
            end            
        end
        
        %% generating feedback with LQR to stabilize the robot
        function generateFeedback(obj,traj)
            
            % calculate the optimal feedback law
            t = traj.t;
            Q = obj.COST.Q;
            R = obj.COST.R;
            Cout = obj.C;
            N = length(t)-1;
            h = t(2) - t(1);
            % get linear time variant matrices around trajectory
            [Ad,Bd] = obj.linearize(traj);
            lqr = LQR(Q,R,Q,Ad,Bd,Cout,N,h,true);
            K = lqr.computeFinHorizonLTV();
            
            traj.K = K;
            
        end
        
    end
        
    
end