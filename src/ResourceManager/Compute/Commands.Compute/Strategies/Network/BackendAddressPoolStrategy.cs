﻿// ----------------------------------------------------------------------------------
//
// Copyright Microsoft Corporation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ----------------------------------------------------------------------------------

using Microsoft.Azure.Commands.Common.Strategies;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Management.Internal.Network.Version2017_10_01;
using Microsoft.Azure.Management.Internal.Network.Version2017_10_01.Models;

namespace Microsoft.Azure.Commands.Common.Strategies.Network
{
    static class BackendAddressPoolStrategy
    {
        public static NestedResourceStrategy<BackendAddressPool, LoadBalancer> Strategy { get; }
            = NestedResourceStrategy.Create<BackendAddressPool, LoadBalancer>(
        provider: "backendAddressPools",
        get: (lb, name) => lb.BackendAddressPools?.FirstOrDefault(s => s?.Name == name),
        createOrUpdate: (lb, name, backendConfigurationPool) =>
        {
            backendConfigurationPool.Name = name;
            if (lb.BackendAddressPools == null)
            {
                lb.BackendAddressPools = new List<BackendAddressPool> { backendConfigurationPool };
                return;
            }
            var b = lb
                .BackendAddressPools
                .Select((bn, i) => new { bn, i })
                .FirstOrDefault(p => p.bn.Name == name);

            if (b != null)
            {
                lb.BackendAddressPools[b.i] = backendConfigurationPool;
                return;
            }
            lb.BackendAddressPools.Add(backendConfigurationPool);
        });

        public static NestedResourceConfig<BackendAddressPool, LoadBalancer> CreateBackendAddressPool(
            this ResourceConfig<LoadBalancer> loadBalancer,
            string name)
                => Strategy.CreateConfig(
                    parent: loadBalancer,
                    name: name,
                    createModel: subscriptionId => CreateBackendAddressPoolConfig(backendPoolName:name , subscriptionId: subscriptionId));

        internal static BackendAddressPool CreateBackendAddressPoolConfig(
            string backendPoolName,
            string subscriptionId)
        {
            var backendAddressPool = new BackendAddressPool();
            backendAddressPool.Name = backendPoolName;

            backendAddressPool.Id =
                LoadBalancerStrategy.GetResourceNotSetId(
                    subscriptionId,
                    LoadBalancerStrategy.LoadBalancerBackendAddressPoolName,
                    backendAddressPool.Name);

            return backendAddressPool;
        }
    }
}
