using ForwardDiff, Statistics, QuadGK, LinearAlgebra, Printf

function inverse_gramian(A,B,a=0.,b=1.)
	W,err = quadgk(x -> exp(A*x)*(B*(B'))*(exp(A*x)'),a,b)		#compute reachability gramian
	inv(factorize(W))
end

function gramian(A,B,a=0.,b=1.)
	W,err = quadgk(x -> exp(A*x)*(B*(B'))*(exp(A*x)'),a,b)	#invert W
end

function energy(x,x0,M,tlim=1.)			#objective function for minimization
	fin = exp(A*tlim)*x0
	((fin - x)' * M * (fin - x))[1]
end

function median_projector(x,eta)		#projection onto C = {x in R^n | median(x) >= eta}
	med = median(x)
	xnew = copy(x)
	n = size(x,1)
	if med < eta				#otherwise no need to project
		medians = 0
		xnew = copy(x)
		indices = Int64[]		#stores the indices of elements which are equal to median
		for i in 1:n			#count number of elts equal to median
			if x[i] == copy(med)
				medians+=1
				append!(indices,i)
			elseif x[i] > med && x[i] < eta
				xnew[i] = copy(eta)
			end
		end

		j = 1
		while median(xnew) < eta && j <= n
			xnew[indices[j]] = copy(eta)
			j+=1
		end
	end
	return(xnew)
end

function gradient(func,x,h=1e-8)		# fixed differences
	it = 1
	n = size(x,1)
	grad = Float64[]
	while it <= n
		xh = copy(x)
		xh[it] = x[it] + h
		append!(grad,(func(xh) - func(x)))
		it += 1
	end
	grad*(1/h)
end

function pgd_optimizer(objective, projector, state0; max_step_size = 5e-1, crit = 1e-5, maxit = 100000)
	diff = crit + 1.			#performs pgd optimization
	it = 0
	state1 = copy(state0)
	while diff > crit && it < maxit
		state0 = copy(state1)
		grad = ForwardDiff.gradient(objective,state1)
		step_size = copy(max_step_size)
		step = step_size*grad
		state1 = projector(state0 - step)
		halvings = 0
		while objective(state1) - objective(state0) > 0. && halvings < 100000
			step_size /= 2
			step = step_size*grad
			state1 = projector(state0 - step)
			halvings += 1
		end
		diff = norm(state1 - state0)
		it +=1
	end
	if it == maxit
		@printf "Maximum iterations reached"
	end
	gradient = ForwardDiff.gradient(objective,state1)
	return(state1)
end


function min_energy(B,A,x0,eta;t0=0.,t1=1.)
	n = Int(sqrt(length(A)))
	B0 = reshape(B,n,Int(length(B)/n))
	W,err = gramian(A,B0)

	me = (sum(exp(A*(t1-t0))*x0) - n*eta)^2 / sum(W)
	return me
end

function derivative_N(B,ND)
	dndb = 4*(tr(B' * B) - ND).*B
	return dndb
end

function tangent_projection(Matrix,B,ND)
	v = reshape(Matrix,length(Matrix),1)
	S = reshape(derivative_N(B,ND),length(Matrix),1)
	S2 = reshape(pinv(S),1,length(Matrix))
	P = (I - S*S2) * v
	return P
end

function sphere_projection(B,Mpe)
	G = sqrt(Mpe / tr(B'*B)) *B
	return G
end

function pgme(A,B0,x0,eta,nD;tol=1e-20,initstep=0.01)
	M = nD + 1e-10
	B1 = sphere_projection(B0,M)
	n = Int(sqrt(length(A)))
	m = Int(length(B)/n)
	objective(x) = min_energy(x,A,x0,eta)
	costheta = 0.
	numits = 0
	while 1-costheta > tol
		step = copy(initstep)
		B0 = copy(B1)
		B0V = reshape(B0,length(B0),1)
		grad = ForwardDiff.gradient(objective,B0V)
		proj_grad = tangent_projection(grad,B0,M)
		inter = B0V - step*proj_grad
		B1 = sphere_projection(reshape(inter,n,m),M)
		B1V = reshape(B1,length(B1),1)
		costheta = dot(B1V,B0V) / (norm(B1V)*norm(B0V))
		numits+=1
	end
	return B1,numits
end

function nested_pgm(A,B0,x0,eta,nD;tol=1e-5,initstep=0.01)
	M = nD + 1e-10
	B1 = sphere_projection(B0,M)
	n = Int(sqrt(length(A)))
	m = Int(length(B)/n)
	objective(x) = energy(pgd_optimizer(y -> energy(y,x0,inverse_gramian(A,reshape(x,n,m))),projector,xstar),x0,inverse_gramian(A,reshape(x,n,m)))
	costheta = 0.
	numits = 0
	while 1-costheta > tol
		step = copy(initstep)
		B0 = copy(B1)
		B0V = reshape(B0,length(B0),1)
		grad = ForwardDiff.gradient(objective,B0V)
		proj_grad = tangent_projection(grad,B0,M)
		inter = B0V - step*proj_grad
		B1 = sphere_projection(reshape(inter,n,m),M)
		B1V = reshape(B1,length(B1),1)
		costheta = dot(B1V,B0V) / (norm(B1V)*norm(B0V))
		numits+=1
	end
	return B1,numits
end
